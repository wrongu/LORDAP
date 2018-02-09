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
% - recompute - boolean flag to force a call to func() even if cached result exists (default false)
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

if nargin < 3, options = struct(); end

%% Configuration and initialization

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

% 'dependencies' tracks what 'loadOrRun' functions are called above the current one, so that if the
% current one is changed we can detect from 'higher' ones that they must be recomputed. Each entry
% maps from a function name (funcName) to the .m source file(s) of its dependencie(s).
metaFile = fullfile(options.metaPath, 'dependencies.mat');
if exist(metaFile, 'file')
    contents = load(metaFile);
    dependencies = contents.dependencies;
    if options.verbose == 1
        disp(['Loaded ''callerDependencies'' from ' metaFile]);
    elseif options.verbose == 2
        fprintf('Loaded dependencies from %s:\n', metaFile);
        for k=keys(dependencies)
            fprintf('\t%s -> %s\n', k{1}, repr(dependencies(k{1}), 0));
        end
    end
else
    dependencies = containers.Map();
    if options.verbose
        disp('No metadata file exists yet - starting with empty dependencies');
    end
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

% A function depends on its own source file (if it exists)
if ~isKey(dependencies, keyFuncName)
    if hasSource
        dependencies(keyFuncName) = {sourceFile};
    else
        dependencies(keyFuncName) = {};
    end
end
    
% Search up the stack trace for other calls to 'loadOrRun' to populate dependencies
stack = dbstack();
for i=2:length(stack)
    if strcmpi(stack(i).name, 'loadorrun')
        callerFuncName = stack(i-1).name;
        if ~isempty(sourceFile) && exist(sourceFile, 'file') && ~ismember(sourceFile, dependencies(callerFuncName))
            % Note: 'callerFuncName' should always be a key of 'dependencies' since it was already
            % called higher in the stack.
            dependencies(callerFuncName) = horzcat(dependencies(callerFuncName), {sourceFile});
        end
    end
end

save(metaFile, 'dependencies');

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

if options.verbose == 2
    disp(['Full UID is ''' uid '''']);
    if isHashed
        disp(['UID hashed to ''' uidFinal '''']);
    end
end

%% Check modification times and (maybe) remove cache file if dependencies changed

if ~strcmpi(options.onDependencyChange, 'ignore')
    if (exist(cacheFile, 'file') || exist(errorFile, 'file')) && isKey(dependencies, keyFuncName)
        % Get list of dependencies' source files to compare against the existing cache file (this
        % includes the source file of 'func').
        dependencySources = dependencies(keyFuncName);
        
        for i=1:length(dependencySources)
            removeCacheIfSourceChanged(options, cacheFile, dependencySources{i});
            % Also remove error files if dependencies changed since the error may now be fixed.
            removeCacheIfSourceChanged(options, errorFile, dependencySources{i});
        end
    end
end

%% Determine whether a call to func is needed

doCompute = ~exist(cacheFile, 'file') || options.recompute;

% Check for hash collision. Note that cacheFile might be large, so we separately save the full uid
% in the '.id.mat' file, which is very fast to load and verify.
if exist(idFile, 'file')
    idContents = load(idFile);
    if ~strcmp(idContents.uid, uid)
        warning('Hash collision!! Original uids:\n\t%s\n\t%s', idContents.uid, uid);
        doCompute = true;
    end
end

%% If last call to func was an error and errorHandling is set to 'cache', rethrow the previous error immediately

if strcmpi(options.errorHandling, 'cache') && exist(errorFile, 'file')
    f = fopen(errorFile, 'r');
    errorText = fread(f, inf, 'uint8=>char');
    fclose(f);
    error(errorText(:)');
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
            delete(errorFile);
        end
    catch e
        if options.verbose
            fprintf('error!\n');
        end
        
        % Save text of error to file
        errorText = getReport(e);
        f = fopen(errorFile, 'w');
        fwrite(f, errorText);
        fclose(f);
        
        rethrow(e);
    end
    
    if options.verbose
        fprintf('done. Saving.\n');
    end
    
    % Save results to the file.
    save(cacheFile, 'results');
    if isHashed
        save(idFile, 'uid', '-v7.3');
    end
else
    if options.verbose
        fprintf('Loading cached results from %s...\t\n', cacheFile);
    end
    contents = load(cacheFile);
    if options.verbose
        fprintf('done.\n');
    end
    results = contents.results;
end

varargout = results;
end

function [str, isDefault, isIgnored] = argToString(arg, numPrecision, defaultArg, defaultStr)

% With no default, simply call repr on the input
if nargin < 3
    isDefault = false;
    isIgnored = false;
    str = repr(arg, numPrecision);
    return
elseif nargin < 4
    error('If defaultArg is given, defaultStr must also be given');
end

isIgnored = isequal(defaultArg, []);
isDefault = isequal(arg, defaultArg);

if isIgnored
    str = '';
    return
end

% Here, default was given but does not match. Recurse to each element of the cell array *with
% defaults* as if each element of the cell array is its own arg.
if iscell(arg)
    argParts = cell(1, length(arg));
    defaultParts = false(1, length(arg));
    ignoredParts = false(1, length(arg));
    
    for i=1:length(arg)
        if length(defaultArg) >= i
            [argParts{i}, defaultParts(i), ignoredParts(i)] = ...
                argToString(arg{i}, numPrecision, defaultArg{i}, defaultStr);
        else
            [argParts{i}, defaultParts(i), ignoredParts(i)] = argToString(arg{i}, numPrecision);
        end
    end

    isIgnored = all(ignoredParts);
    isDefault = all(defaultParts(~ignoredParts));
    str = ['{' strjoin(argParts(~ignoredParts), '-') '}'];

% As in the previous case, recurse on each field of the struct.
elseif isstruct(arg)
    fields = fieldnames(arg);
    argParts = cell(1, length(fields));
    defaultParts = false(1, length(fields));
    ignoredParts = false(1, length(arg));
    
    for i=1:length(fields)
        key = fields{i};
        if isfield(defaultArg, key)
            [argParts{i}, defaultParts(i), ignoredParts(i)] = ...
                argToString(arg.(key), numPrecision, defaultArg.(key), defaultStr);
        else
            [argParts{i}, defaultParts(i), ignoredParts(i)] = argToString(arg.(key), numPrecision);
        end
        argParts{i} = [key '=' argParts{i}];
    end

    isIgnored = all(ignoredParts);
    isDefault = all(defaultParts(~ignoredParts));
    % defaultParts are entirely excluded from UID. Since structs have 'key=' prepended, it becomes
    % extremely unlikely that there will be a naming collision when keys are removed.
    str = ['(' strjoin(argParts(~(ignoredParts | defaultParts)), '-') ')'];

% Default was provided for numeric, logical, or string arg but didn't match; simply repr() it.
else
    str = repr(arg, numPrecision);
end

% If arg was its default, check if the string is likely to be shortened by replacing it with the
% 'default string'
if isDefault
    % Replace with default string if (1) arg is a struct, (2) arg is a cell array, or (3) arg is a
    % string that is logner than the default string.
    if isstruct(arg) || iscell(arg) || (ischar(arg) && length(arg) > length(defaultStr))
        str = defaultStr;
    else
        str = repr(arg, numPrecision);
    end
end

% If not ignored, assert that arg was not a Matlab object -- these are not handled by repr().
if ~isIgnored
    assert(~isobject(arg), 'Cannot convert Matlab objects to a UID; use numeric, logical, string, struct, or cell arguments.');
end
end

function s = repr(obj, numPrecision)
% REPR get string representation of input. Input may be numeric, logical, a string, a cell array, or
% a struct.
if isnumeric(obj)
    if isscalar(obj)
        s = num2str(obj, numPrecision);
    else
        s = ['[' strjoin(arrayfun(@(num) num2str(num, numPrecision), obj, 'UniformOutput', false), '-') ']'];
    end
elseif ischar(obj)
    s = strrep(obj, ' ', '_');
elseif islogical(obj)
    if obj
        s = 'T';
    else
        s = 'F';
    end
elseif iscell(obj)
    s = ['{' strjoin(cellfun(@(sub) repr(sub, numPrecision), obj, 'UniformOutput', false), '-') '}'];
elseif isstruct(obj)
    fields = fieldnames(obj);
    sParts = cell(size(fields));
    for i=1:length(fields)
        key = fields{i};
        val = obj.(key);
        sParts{i} = [key '=' repr(val, numPrecision)];
    end
    s = ['(' strjoin(sParts, '-') ')'];
end
end

function removeCacheIfSourceChanged(options, cacheFile, dependencySourceFile)
% Check if sourceFile changed more recently than the saved cached file(s).
sourceInfo = dir(dependencySourceFile);
cacheInfo = dir(cacheFile);

if ~isempty(sourceInfo) && ~isempty(cacheInfo) && cacheInfo.datenum < sourceInfo.datenum
    message = ['Source file ' dependencySourceFile ' changed since the cached results for ' ...
        cacheFile ' were last updated.'];
    switch lower(options.onDependencyChange)
        case {'warn'}
            warning([message ' Delete the cached file if the output is affected!!']);
        case {'autoremove'}
            if options.verbose
                disp([message ' Deleting it now!']);
            end
            delete(cacheFile);
    end
end

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

function hash=string2hash(str,type)
% This function generates a hash value from a text string
%
% hash=string2hash(str,type);
%
% inputs,
%   str : The text string, or array with text strings.
% outputs,
%   hash : The hash value, integer value between 0 and 2^32-1
%   type : Type of has 'djb2' (default) or 'sdbm'
%
% From c-code on : http://www.cse.yorku.ca/~oz/hash.html
%
% djb2
%  this algorithm was first reported by dan bernstein many years ago
%  in comp.lang.c
%
% sdbm
%  this algorithm was created for sdbm (a public-domain reimplementation of
%  ndbm) database library. it was found to do well in scrambling bits,
%  causing better distribution of the keys and fewer splits. it also happens
%  to be a good general hashing function with good distribution.
%
% example,
%
%  hash=string2hash('hello world');
%  disp(hash);
%
% Function is written by D.Kroon University of Twente (June 2010)


% From string to double array
str=double(str);
if(nargin<2), type='djb2'; end
switch(type)
    case 'djb2'
        hash = 5381*ones(size(str,1),1);
        for i=1:size(str,2)
            hash = mod(hash * 33 + str(:,i), 2^32-1);
        end
    case 'sdbm'
        hash = zeros(size(str,1),1);
        for i=1:size(str,2)
            hash = mod(hash * 65599 + str(:,i), 2^32-1);
        end
    otherwise
        error('string_hash:inputs','unknown type');
end
end