function removed = removeCacheIfSourceChanged(options, cacheFile, dependencySourceFile)
% REMOVECACHEIFSOURCECHANGED helper function for loadOrRun. Checks if the given cache file (.mat) or
% the given source file (.m) has a more recent timestamp. Issues a warning or deletes the cached
% file depending on the value of options.onDependencyChange (see loadOrRun)
%
% Copyright (c) 2018 Richard Lange

% Check if sourceFile changed more recently than the saved cached file(s).
sourceInfo = dir(dependencySourceFile);
cacheInfo = dir(cacheFile);

removed = false;

if ~isempty(sourceInfo) && ~isempty(cacheInfo) && cacheInfo.datenum < sourceInfo.datenum
    message = ['Source file ' dependencySourceFile ' changed since the cached results for ' ...
        cacheFile ' were last updated.'];
    switch lower(options.onDependencyChange)
        case {'warn'}
            warning([message ' Delete the cached file if the output is affected!!']);
        case {'autoremove'}
            removed = true;
            if options.verbose && ~options.dryRun
                disp([message ' Deleting it now!']);
            end
            % Only remove files if this isn't a 'dry run'
            if ~options.dryRun
                % Make sure we are holding a lock on the cache file while removing it in case
                % another process is trying to load the same file.
                sem = getsemaphore(cacheFile);
                delete(cacheFile);
                releasesemaphore(sem);
            end
    end
end

end