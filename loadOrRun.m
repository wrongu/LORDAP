function varargout = loadOrRun(func, args, options)
%LOADORRUN load cached results from a file, or compute and save them.
%
% ... = LOADORRUN(func, {arg1, arg2, ..}, options) If the cache file does not exist, computes
% func(arg1, arg2, ..) and saves the results. If it does exist, simply loads the results and returns
% them. Return values are identical to whatever func returns. If func has multiple outputs, the same
% number of outputs must always be captured. For example the following will NOT work:
%
%    x1 = LOADORRUN(@func, args);
%    [x1, x2] = LOADORRUN(@func, args);
%
% but the following WILL work:
%
%    [x1, ~] = LOADORRUN(@func, args);
%    [x1, x2] = LOADORRUN(@func, args);
%
%
% 'options' is an optional struct controlling the behavior of LOADORRUN. It may contain any of the
% following fields:
% - cachePath - where save results (default '.cache/'). Note that the '.' prefix makes the directory
%   hidden on unix and linux systems.
% - metaPath - where to save metadata about function dependencies (default '.meta/')
% - recompute - boolean flag to force a call to func() even if cached result exists, or a datenum
%   timestamp indicating that all files older than this should be recomputed (this allows recompute
%   to be set to the matlab function 'now' to recompute each function once). (default false)
% - verbose - integer flag for level of extra diagnostic messages in range 0-2 (default 0)
% - errorHandling - how to handle errors. Options are 'none' to do nothing, or 'cache' to save and
%   immediately rethrow errors on future calls. The cache option is recommended if the calling
%   function already contains a 'try/catch' block. 'cache' will save the text of the error message
%   in a .error file in the cachePath directory, but does not give access to stack traces (default
%   'none')
% - numPrecision - precision digits for queries based on numerical values (default 4)
% - onDependencyChange - what to do with cached results of functions whose dependencies have been
%   modified. Options are 'ignore' to skip checks, 'warn' to  print a warning, or 'autoremove' to
%   automatically and aggressively delete any upstream file that may have been affected (default
%   'warn')
% - uid - a hard-coded unique identifier for creating the cached file. This overrides the UID that
%   would have been created based on args.
% - defaultArgs - a cell array of the same size or smaller than args. Any args that match those in
%   'options.defaultArgs' will not be added to the UID. Any values in defaultArgs set to [] will
%   always be ignored regardless of value. Defaults are applied recursively to struct or cell array
%   arguments.
% - defaultString - a short string to replace any args that are ignored or have default values.
%   (default 'default')
%
% For example, if options.uid = 'myuid12345', then results will be saved in a file (in the
% options.cachePath directory) called '<funcName>-myuid12345.mat' (where <funcName> is the string
% name of 'func'). When using the 'uid' option, it is the responsibility of the user to ensure that
% distinct function calls are given different IDs. When options.uid is not supplied, a UID is
% automatically constructed from 'args'. Args may be numeric, logical, strings, structs, or cell
% arrays. If at any point a filename becomes too long, it will be hashed to something like
% '<funcName>-AF4D2F80.mat', or some other random string of hex characters.
%
%
% The options.cachePath directory will be populated with
%  1. <uid>.mat    - contains the results of func()
%  2. <uid>.id.mat - contains the true (long) uid. (only used if uid was hashed, and is used to
%                    check for hash collisions)
%  3. <uid>.error  - text contents of an error message if options.errorHandling is 'cache' or
%                    'warn'
%
% Copyright (c) 2018, Richard Lange

if nargin < 3, options = struct(); end

%% Configuration and initialization

% Ensure that dependencies are on the path
if exist('string2hash', 'file') ~= 2, addpath('string2hash'); end
if exist('getsemaphore', 'file') ~= 2, addpath('semaphore'); end

% Set up default options.
if ~isfield(options, 'cachePath'), options.cachePath = fullfile(pwd, '.cache'); end
if ~isfield(options, 'metaPath'), options.metaPath = fullfile(pwd, '.meta'); end
if ~isfield(options, 'recompute'), options.recompute = false; end
if ~isfield(options, 'verbose'), options.verbose = false; end
if ~isfield(options, 'errorHandling'), options.errorHandling = 'none'; end
if ~isfield(options, 'numPrecision'), options.numPrecision = 4; end
if ~isfield(options, 'onDependencyChange'), options.onDependencyChange = 'warn'; end
if ~isfield(options, 'defaultArgs'), options.defaultArgs = {}; end
if ~isfield(options, 'defaultString'), options.defaultString = 'default'; end

% Check inputs.
assert(iscell(args), 'loadOrRun(@fun, args): args must be a cell array');
assert(any(options.verbose == [0 1 2]));
assert(any(strcmpi(options.errorHandling, {'cache', 'none'})));
assert(any(strcmpi(options.onDependencyChange, {'ignore', 'warn', 'autoremove'})));

% Create necessary directories if they don't exist yet.
if ~exist(options.cachePath, 'dir')
    if options.verbose
        disp(['Caching directory ' options.cachePath ' does not exist. Creating it now.']);
    end
    mkdir(options.cachePath);
end

if ~exist(options.metaPath, 'dir')
    if options.verbose
        disp(['Metadata directory ' options.metaPath ' does not exist. Creating it now.']);
    end
    mkdir(options.metaPath);
end

if islogical(options.recompute)
    if options.recompute
        recomputeTime = inf;
    else
        recomputeTime = -inf;
    end
else
    recomputeTime = options.recompute;
end

%% Update dependencies metadata by searching up the current call stack

% Get information about the true name of 'func', its source file, etc.
funcInfo = functions(func);
funcName = funcInfo.function;
sourceFile = funcInfo.file;
isPackage = contains(funcName, '.');
hasSource = true;

if isPackage
    % Fix odd behavior in Matlab where functions(@package.func) cannot find the source of a file,
    % but which(functions(@package.func).function) can find it.
    sourceFile = which(funcName);
    
    % Further fix odd behavior where dbstack() from within package functions strips off the name of
    % the package - as far as monitoring dependencies goes, this means that dependencies of
    % packageA.packageFun and packageB.packageFun will be 'merged', which could trigger more
    % warnings and updates than is strictly necessary.
    nameParts = strsplit(funcName, '.');
    if options.verbose
        warning(['Note: package functions have surprising behavior! %s() will be stored as just '...
            '''%s'' when checking for changed dependencies - loadOrRun cannot tell the difference '...
            'between this and a function of the same name in another package!!'], funcName, nameParts{end});
    end
    keyFuncName = nameParts{end};
else
    keyFuncName = funcName;
end

if isempty(sourceFile)
    if ~exist(funcName, 'builtin')
        warning('Source file for %s cannot be inferred (is it an anonymous function??)\n', funcName);
    elseif options.verbose == 2
        fprintf('%s appears to be a built-in function. loadOrRun will not try to check for changes to its source.\n', funcName);
    end
    hasSource = false;
elseif ~exist(sourceFile, 'file')
    warning('Source file for %s is not visible from the current path settings (source: ''%s'')\n', funcName, sourceFile);
    hasSource = false;
end

% 'dependencies' tracks what 'loadOrRun' functions are called above the current one, so that if the
% current one is changed we can detect from 'higher' ones that they must be recomputed. A file named
% <funcName>-sourceDependencies.mat will contain a cell array of paths to .m files that <funcName>
% depends on.

if hasSource
    % First, add own source file as a dependency to track
    addSourceDependency(keyFuncName, sourceFile, options);
    
    % Next, search up the stack trace for other calls to 'loadOrRun' to flag this file as a
    % dependency of its parent function(s)
    stack = dbstack();
    for i=2:length(stack)
        if strcmpi(stack(i).name, 'loadorrun')
            callerFuncName = stack(i-1).name;
            addSourceDependency(callerFuncName, sourceFile, options);
        end
    end
end

%% Get UID or create from args

if isfield(options, 'uid')
    uid = options.uid;
    
    % Remove '.mat' extension if it is given in the uid.
    if length(uid) > 4 && strcmp(options.uid(end-3:end), '.mat')
        uid = uid(1:end-4);
    end
else
    % Call 'argToString' as if the cell array of args is a single arg, which will return a string
    % representation of all args surrounded with curly braces since it is a cell array.
    uid = argToString(args, options.numPrecision, options.defaultArgs, options.defaultString);
    
    % Strip the curly braces.
    if strcmp(uid(1), '{')
        uid = uid(2:end-1);
    end
end

% Max name length on unix is 255. Max length is reduced by length(funcName) because '<funcName>-'
% will be prepended. 6 additional characters are subtracted off for the '.error' extension.
MAX_FILENAME_LENGTH = 255 - (length(funcName) + 1) - 6;
[uidFinal, isHashed] = maybeHash(uid, MAX_FILENAME_LENGTH);

% After sorting out the uid and hashing, prepend '<funcName>-' and get filenames.
uidFinal = [funcName '-' uidFinal];
cacheFile = fullfile(options.cachePath, [uidFinal '.mat']);
idFile = fullfile(options.cachePath, [uidFinal '.id.mat']);
errorFile = fullfile(options.cachePath, [uidFinal '.error']);

cacheSem = fullfile(options.metaPath, uidFinal);
idSem = fullfile(options.metaPath, [uidFinal '.id']);
errorSem = fullfile(options.metaPath, [uidFinal '.error']);

if options.verbose == 2
    disp(['Full UID is ''' uid '''']);
    if isHashed
        disp(['UID hashed to ''' uidFinal '''']);
    end
end

%% Check modification times and (maybe) remove cache file if dependencies changed

if ~strcmpi(options.onDependencyChange, 'ignore')
    depFile = fullfile(options.metaPath, [keyFuncName '-sourceDependencies.mat']);
    if (exist(cacheFile, 'file') || exist(errorFile, 'file')) && exist(depFile, 'file')
        % Get list of dependencies' source files to compare against the existing cache file (this
        % includes the source file of 'func' itself).
        sem = getsemaphore(depFile);
        contents = load(depFile);
        releasesemaphore(sem);
        dependencies = contents.dependencies;
        
        if options.verbose == 2
            fprintf('Loaded dependencies from %s:\n', depFile);
            for i=1:length(dependencies)
                fprintf('\t%s -> %s\n', keyFuncName, dependencies{i});
            end
        end
        
        for i=1:length(dependencies)
            removeCacheIfSourceChanged(options, cacheFile, dependencies{i});
            % Also remove error files if dependencies changed since the error may now be fixed.
            removeCacheIfSourceChanged(options, errorFile, dependencies{i});
        end
    end
end

%% If last call to func was an error and errorHandling is set to 'cache', rethrow the previous error immediately

if strcmpi(options.errorHandling, 'cache') && exist(errorFile, 'file')
    sem = getsemaphore(errorSem);
    f = fopen(errorFile, 'r');
    errorText = fread(f, inf, 'uint8=>char');
    fclose(f);
    releasesemaphore(sem);
    error(errorText(:)');
end

%% Determine whether a call to func is needed

cacheInfo = dir(cacheFile);
doCompute = ~exist(cacheFile, 'file') || (cacheInfo.datenum < recomputeTime);

if doCompute && options.verbose == 2
    if ~exist(cacheFile, 'file')
        fprintf('Reason: no cache file\n');
    elseif cacheInfo.datenum < recomputeTime
        fprintf('Reason: old cache file\n');
    else
        fprintf('Reason: ???\n');
    end
end

% Check for hash collision. Note that cacheFile might be large, so we separately save the full uid
% in the '.id.mat' file, which is very fast to load and verify.
if exist(idFile, 'file')
    sem = getsemaphore(idSem);
    idContents = load(idFile);
    releasesemaphore(sem);
    if ~strcmp(idContents.uid, uid)
        warning('Hash collision!! Original uids:\n\t%s\n\t%s', idContents.uid, uid);
        doCompute = true;
    end
end

%% Call func or load cached results.
if doCompute
    % Call func(args) and capture as many return values as have been requested by whoever called
    % this function.
    if options.verbose
        fprintf('Calling %s with %d outputs...\t\n', funcName, nargout);
    end
    results = cell(1, nargout);
    
    try
        [results{:}] = func(args{:});
        
        if exist(errorFile, 'file')
            sem = getsemaphore(errorSem);
            delete(errorFile);
            releasesemaphore(sem);
        end
    catch e
        if options.verbose
            fprintf('error!\n');
        end
        
        % Save text of error to file
        errorText = getReport(e);
        sem = getsemaphore(errorSem);
        f = fopen(errorFile, 'w');
        fwrite(f, errorText);
        fclose(f);
        releasesemaphore(sem);
        
        rethrow(e);
    end
    
    if options.verbose
        fprintf('done. Saving to %s...\n', cacheFile);
    end
    
    % Save results to the file.
    sem = getsemaphore(cacheSem);
    save(cacheFile, 'results');
    releasesemaphore(sem);
    if isHashed
        sem = getsemaphore(idSem);
        save(idFile, 'uid', '-v7.3');
        releasesemaphore(sem);
    end
else
    if options.verbose
        fprintf('Loading cached results from %s...\t\n', cacheFile);
    end
    sem = getsemaphore(cacheSem);
    contents = load(cacheFile);
    releasesemaphore(sem);
    if options.verbose
        fprintf('done.\n');
    end
    results = contents.results;
end

varargout = results;
end

function [uid, isHashed] = maybeHash( uid, maxLength )
%MAYBE_HASH hashes uid if its length is larger than maxLength (default 250)
if nargin < 2, maxLength = 250; end

if length(uid) > maxLength
    % Hash the string.
    uid = sprintf('%X', string2hash(uid));
    isHashed = true;
else
    % It's short enough; keep the string as-is.
    isHashed = false;
end

end
