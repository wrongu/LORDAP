function removeCacheIfSourceChanged(options, cacheFile, dependencySourceFile)
% REMOVECACHEIFSOURCECHANGED helper function for LOADORRUN. Checks if the given cache file (.mat) or
% the given source file (.m) has a more recent timestamp. Issues a warning or deletes the cached
% file depending on the value of options.onDependencyChange (see LOADORRUN)
%
% Copyright (c) 2018 Richard Lange

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