function dependencies = addSourceDependency(funcName, sourceFile, options)
%ADDSOURCEDEPENDENCY helper function for loadOrRun for safely marking a source .m file to the list
%of dependencies for the given function name.
%
%Copyright (c) 2018 Richard Lange

depFile = fullfile(options.metaPath, [funcName '-sourceDependencies.mat']);

if exist(depFile, 'file')
    contents = load(depFile);
    dependencies = horzcat(contents.dependencies, {sourceFile});
else
    dependencies = {sourceFile};
end

dependencies = unique(dependencies);
save(depFile, 'dependencies');

end