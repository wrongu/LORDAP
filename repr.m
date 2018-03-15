function s = repr(obj, numPrecision)
% REPR get string representation of input. Input may be numeric, logical, a string, a cell array, or
% a struct. Objects are converted to structs, keeping field names and values.
%
% Copyright (c) 2018 Richard Lange

if isobject(obj)
    obj = struct(obj);
end

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