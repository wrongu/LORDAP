function dependencies = addSourceDependency(funcName, sourceFile, options)
%ADDSOURCEDEPENDENCY helper function for loadOrRun for safely marking a source .m file to the list
%of dependencies for the given function name.
%
%Copyright (c) 2018 Richard Lange

depFile = fullfile(options.metaPath, [funcName '-sourceDependencies.mat']);

if exist(depFile, 'file')
    sem = getsemaphore(depFile);
    contents = load(depFile);
    releasesemaphore(sem);
    dependencies = contents.dependencies;
    
    % Only add 'sourceFile' if it is not already in 'dependencies'
    if ~any(strcmpi(sourceFile, contents.dependencies))
        dependencies = unique(horzcat(dependencies, {sourceFile}));
    
        sem = getsemaphore(depFile);
        save(depFile, 'dependencies');
        releasesemaphore(sem);
    end
else
    dependencies = {sourceFile};
    
    sem = getsemaphore(depFile);
    save(depFile, 'dependencies');
    releasesemaphore(sem);
end


end