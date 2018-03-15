function [str, isDefault, isIgnored] = argToString(arg, numPrecision, defaultArg, defaultStr)
% ARGTOSTRING helper function for LOADORRUN. Recursively converts function arguments into a string
% identifier, taking 'default' values into account. (See LOADORRUN).
%
% Copyright (c) 2018 Richard Lange

% With no default, simply call repr on the input
if nargin < 3
    isDefault = false;
    isIgnored = false;
    str = repr(arg, numPrecision);
    return
elseif nargin < 4
    error('If defaultArg is given, defaultStr must also be given');
end

if isobject(arg)
    arg = struct(arg);
    if nargin >= 3 && isobject(defaultArg)
        defaultArg = struct(defaultArg);
    end
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
end