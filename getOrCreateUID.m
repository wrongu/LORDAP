function uid = getOrCreateUID(args, options)
%GETORCREATEUID helper function for loadOrRun to get or create a unique identifier (UID) for a
%function call. If options.uid is supplied, that value is used. Otherwise, constructs a string
%identifier from the cell array of function arguments, using options.numPrecision,
%options.defaultArgs, options.defaultString to further control its behavior.

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
end