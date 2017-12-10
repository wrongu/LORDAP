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
% 'options' is a struct. It may contain the following fields to control the behavior of LOADORRUN:
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
% - query - a query struct (see below). 'uid' and 'query' are mutually exclusive, and supplying both
%   will result in an error. At least one is required.
% - defaultQuery - a query struct (see below). Any values in  'options.query' that match those in
%   'options.defaultQuery' will not be added to the UID. (default empty struct)
% - uid - a hard-coded unique identifier for creating the cached file. 'uid' and 'query' are
%   mutually exclusive, and supplying both will result in an error.
%
%
% For example, if options.uid = 'myuid12345', then results will be saved in a file (in the
% options.cachePath directory) called '<funcName>-myuid12345.mat' (where <funcName> is the string
% name of 'func'). When using the 'uid' option, it is the responsibility of the user to ensure that
% distinct function calls are given different IDs. Use 'options.query' to automate the construction
% of an identifier. For example, if query.a = 7 and query.b = 'foo', then results will be saved in a
% file called '<funcName>-a=7-b=foo.mat'. In general, a "query struct" defines parameter names and
% values and is used to automatically construct a uid. Values of a query struct may be numeric,
% strings, another struct, or a cell array. Query fields and function names should be kept short to
% avoid long filenames. If at any point a filename becomes too long, it will be hashed to something
% like '<funcName>-AF4D2F80.mat', or some other random string of hex characters.
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

% Set up default options
if ~isfield(options, 'cachePath'), options.cachePath = fullfile(pwd, '.cache'); end
if ~isfield(options, 'metaPath'), options.metaPath = fullfile(pwd, '.meta'); end
if ~isfield(options, 'recompute'), options.recompute = false; end
if ~isfield(options, 'verbose'), options.verbose = false; end
if ~isfield(options, 'errorHandling'), options.errorHandling = 'none'; end
if ~isfield(options, 'numPrecision'), options.numPrecision = 4; end
if ~isfield(options, 'onDependencyChange'), options.onDependencyChange = 'warn'; end
if ~isfield(options, 'defaultQuery'), options.defaultQuery = struct(); end
if ~isfield(options, 'uid') && ~isfield(options, 'query')
    error('Must specify either a string uid or a query struct!');
elseif isfield(options, 'uid') && isfield(options, 'query')
    error('Must only specify one of ''uid'' or ''query''!');
end

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

% 'callerDependencies' tracks what 'loadOrRun' functions are called above the current one, so that
% if the current one is changed we can detect that 'higher' ones must be updated as well. Each entry
% in callerDependencies will map from funcName to {callerName1, callerName2} (a cell array of string
% names of 'loadOrRun' functions higher up in the stack). 'calleeDependencies' is the reverse,
% mapping from high a level function to its dependencies' source files.
metaFile = fullfile(options.metaPath, 'dependencies.mat');
if exist(metaFile, 'file')
    contents = load(metaFile);
    callerDependencies = contents.callerDependencies;
    calleeDependencies = contents.calleeDependencies;
    if options.verbose == 1
        disp(['Loaded ''callerDependencies'' from ' metaFile]);
    elseif options.verbose == 2
        fprintf('Loaded dependencies from %s. Caller:\n', metaFile);
        for k=keys(callerDependencies)
            fprintf('\t%s -> %s\n', k{1}, repr(callerDependencies(k{1}), options.numPrecision));
        end
        fprintf('Loaded dependencies from %s. Callee:\n', metaFile);
        for k=keys(calleeDependencies)
            fprintf('\t%s -> %s\n', k{1}, repr(calleeDependencies(k{1}), options.numPrecision));
        end
    end
else
    callerDependencies = containers.Map();
    calleeDependencies = containers.Map();
    if options.verbose
        disp('No metadata file exists yet - starting with empty dependencies');
    end
end

%% Update dependencies metadata by searching up the current call stack

% Get information about the true name of 'func', its source file, etc.
funcInfo = functions(func);
funcName = funcInfo.function;

if ~isKey(callerDependencies, funcName)
    callerDependencies(funcName) = {};
end

if ~isKey(calleeDependencies, funcName)
    calleeDependencies(funcName) = {};
end

% Search up the stack trace for other calls to 'loadOrRun'
stack = dbstack();
for i=2:length(stack)
    if strcmpi(stack(i).name, 'loadorrun')
        callerFuncName = stack(i-1).name;
        callerNames = callerDependencies(funcName);
        callerDependencies(funcName) = horzcat(callerNames, {callerFuncName});
        
        if ~isempty(funcInfo.file)
            callees = calleeDependencies(callerFuncName);
            calleeDependencies(callerFuncName) = horzcat(callees, {funcInfo.file});
        elseif options.verbose == 2
            warning('Source file unknown for %s (is it an anonymous- or package-function?)\n', funcName);
        end
    end
end
save(metaFile, 'callerDependencies', 'calleeDependencies');

%% Get UID or create from query

% Read or construct uid for this call.
if isfield(options, 'uid')
    uid = options.uid;
else
    % Construct uid from function name and query
    uid = queryToUID(options.query, options.defaultQuery, options.numPrecision);
end

[~, uid, ext] = fileparts(uid);
% if the uid itself contains a '.' and does not end in '.mat', it will
% be split across 'uid' and 'ext'.
if ~strcmp(ext, '.mat'), uid = strcat(uid, ext); end

% Max name length on unix is 255. Max length is reduced by length(funcName) because '<funcName>-'
% will be prepended. 6 additional characters are subtracted off for the '.mat' or '.error' suffix
MAX_FILENAME_LENGTH = 255 - (length(funcName) + 1) - 6;
[uidFinal, isHashed] = maybeHash(uid, MAX_FILENAME_LENGTH);

% After sorting out the query struct and hashing, prepend '<funcName>-' and get filenames.
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

%% Check modification times and (maybe) remove files affected by change

sourceInfo = dir(funcInfo.file);
cacheInfo = dir(cacheFile);

if ~strcmpi(options.onDependencyChange, 'ignore')
    %% Part 0: check source of function itself
    if ~isempty(cacheInfo) && ~isempty(sourceInfo)
        removeCacheIfSourceChanged(options, funcName, funcInfo.file);
    end
    
    %% Part 1 (down the stack): check if anything that this function depends on has changed
    if ~isempty(cacheInfo) && isKey(calleeDependencies, funcName)
        % Get list of dependencies' source files to compare against the existing cache file.
        depdendencySources = calleeDependencies(funcName);
        
        for i=1:length(depdendencySources)
            removeCacheIfSourceChanged(options, funcName, depdendencySources{i});
        end
    end
    
    %% Part 2 (up the stack): if this function has changed, update anything that depends on it
    if ~isempty(sourceInfo) && isKey(callerDependencies, funcName)
        % Get list of functions 'higher' in the stack that have called this function.
        callerNames = callerDependencies(funcName);
        
        for i=1:length(callerNames)
            removeCacheIfSourceChanged(options, callerNames{i}, funcInfo.file);
        end
    elseif options.verbose == 2
        warning('Source file of %s is unknown; dependency checks cannot be done\n', funcName);
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
    errorText = fread(f);
    fclose(f);
    error(errorText);
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

function uid = queryToUID(query, defaultQuery, numPrecision)
fields = fieldnames(query);
uidParts = cell(size(fields));
isDefault = false(size(fields));
for i=1:length(fields)
    key = fields{i};
    val = query.(key);
    if isfield(defaultQuery, key) && isequal(val, defaultQuery.(key))
        isDefault(i) = true;
    else
        uidParts{i} = [key '=' repr(val, numPrecision)];
    end
end
if all(isDefault)
    uid = 'default';
else
    uid = strjoin(uidParts(~isDefault), '-');
end
end

function s = repr(obj, numPrecision)
% REPR get string representation of input. Input may be numeric, a string,
% a cell array, or another struct.
if isnumeric(obj)
    if isscalar(obj)
        s = num2str(obj, numPrecision);
    else
        s = ['[' strjoin(arrayfun(@(num) num2str(num, numPrecision), obj, 'UniformOutput', false), ',') ']'];
    end
elseif ischar(obj)
    s = strrep(obj, ' ', '_');
elseif iscell(obj)
    s = ['{' strjoin(cellfun(@(sub) repr(sub, numPrecision), obj, 'UniformOutput', false), ',') '}'];
elseif isstruct(obj)
    fields = fieldnames(obj);
    sParts = cell(size(fields));
    for i=1:length(fields)
        key = fields{i};
        val = obj.(key);
        sParts{i} = [key '=' repr(val, numPrecision)];
    end
    s = ['(' strjoin(sParts, ',') ')'];
end
end

function removeCacheIfSourceChanged(options, funcName, dependencySourceFile)
% Check if sourceFile changed more recently than the saved cached file(s).
sourceInfo = dir(dependencySourceFile);
cacheFilePattern = fullfile(options.cachePath, [funcName '-*']);
cacheFilesInfo = dir(cacheFilePattern);
oldestCacheFile = min([cacheFilesInfo.datenum]);

if ~isempty(sourceInfo) && ~isempty(oldestCacheFile) && oldestCacheFile < sourceInfo.datenum
    message = ['Source file ' dependencySourceFile ' changed since the cached results for ' ...
        funcName ' were last updated. Delete the cached file if the output is affected!!'];
    switch lower(options.onDependencyChange)
        case {'warn'}
            warning(message);
        case {'autoremove'}
            if options.verbose
                disp(message);
            end
            removeCacheFilesForFunction(options, funcName, sourceInfo.datenum);
    end
end

end

function removeCacheFilesForFunction(options, funcName, beforeTimestamp)
pattern = fullfile(options.cachePath, [funcName '-*']);
if options.verbose
    fprintf('Removing files for %s()\n', funcName);
end
files = dir(pattern);
for i=1:length(files)
    if files(i).datenum < beforeTimestamp
        if options.verbose == 2
            fprintf('\tremoving %s\n', files(i).name);
        end
        delete(fullfile(files(i).folder, files(i).name));
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