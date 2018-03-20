function s = emptyfile(filename)
%EMPTYFILE create an empty file with the given filename.

try
    fh = fopen(filename, 'w');
    fclose(fh);
    s = 0;
catch
    s = -1;
end

end