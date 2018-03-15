% UPDATED DEPENDENCIES UNIT TESTS FOR LOADORRUN

%% Put testing files on the path

if ~exist('twoOut', 'file')
    addpath('testing');
end

%% Test updated dependency -- call from top

options = struct();
options.onDependencyChange = 'warn';
options.defaultArgs = {[]}; % ignore first 'options' arg but not second numeric arg.
val = loadOrRun(@dependencyTop, {options, 1}, options);
assert(val == 2);
assert(exist(fullfile('.cache', 'dependencyBottom-1.mat'), 'file') > 0);
assert(exist(fullfile('.cache', 'dependencyTop-1.mat'), 'file') > 0);

% Modify 'bottom' (update it's timestamp with 'touch')
pause(1);
!touch testing/dependencyBottom.m

sourceInfo = dir(fullfile('testing', 'dependencyBottom.m'));
cacheInfo = dir(fullfile('.cache', 'dependencyBottom-1.mat'));
assert(cacheInfo.datenum < sourceInfo.datenum, 'something went wrong with system call ''touch''');

val = loadOrRun(@dependencyTop, {options, 1}, options);
assert(val == 2);

% Warning should have been issued, and .mat file should NOT have been recomputed
sourceInfo = dir(fullfile('testing', 'dependencyBottom.m'));
cacheInfo = dir(fullfile('.cache', 'dependencyBottom-1.mat'));
assert(cacheInfo.datenum < sourceInfo.datenum, 'in ''warn'' mode, dependency change should not trigger an update');

options.onDependencyChange = 'autoremove';
pause(1);
val = loadOrRun(@dependencyTop, {options, 1}, options);
assert(val == 2);
sourceInfo = dir(fullfile('testing', 'dependencyBottom.m'));
cacheInfoBottom = dir(fullfile('.cache', 'dependencyBottom-1.mat'));
assert(cacheInfoBottom.datenum > sourceInfo.datenum, 'in ''autoremove'' mode, dependency change SHOULD trigger an update');
cacheInfoTop = dir(fullfile('.cache', 'dependencyTop-1.mat'));
assert(cacheInfoTop.datenum > sourceInfo.datenum, 'in ''autoremove'' mode, dependency change SHOULD trigger an update');

rmdir('.cache', 's');
rmdir('.meta', 's');

%% Test updated dependency -- call from bottom

options = struct();
options.onDependencyChange = 'warn';
options.defaultArgs = {[]}; % ignore first 'options' arg but not second numeric arg.
val = loadOrRun(@dependencyTop, {options, 1}, options);
assert(val == 2);
assert(exist(fullfile('.cache', 'dependencyBottom-1.mat'), 'file') > 0);
assert(exist(fullfile('.cache', 'dependencyTop-1.mat'), 'file') > 0);

% Modify 'bottom' (update it's timestamp with 'touch')
pause(1);
!touch testing/dependencyBottom.m

sourceInfo = dir(fullfile('testing', 'dependencyBottom.m'));
cacheInfo = dir(fullfile('.cache', 'dependencyTop-1.mat'));
assert(cacheInfo.datenum < sourceInfo.datenum, 'something went wrong with system call ''touch''');

% Directly call bottom of call stack
options.defaultArgs = {};
val = loadOrRun(@dependencyBottom, {1}, options);
assert(val == 2);

% Warning should have been issued, and both .mat files should still exist
assert(exist(fullfile('.cache', 'dependencyTop-1.mat'), 'file') > 0, 'in ''warn'' mode, dependency change should not trigger an update');
assert(exist(fullfile('.cache', 'dependencyBottom-1.mat'), 'file') > 0, 'in ''warn'' mode, dependency change should not trigger an update');

options.onDependencyChange = 'autoremove';
pause(1);
val = loadOrRun(@dependencyBottom, {1}, options);
assert(val == 2);
cacheInfo = dir(fullfile('.cache', 'dependencyBottom-1.mat'));
assert(cacheInfo.datenum > sourceInfo.datenum, 'in ''autoremove'' mode, cache for ''bottom'' should have been updated!');
assert(exist(fullfile('.cache', 'dependencyTop-1.mat'), 'file') > 0, 'expected behavior is that calling ''bottom'' does not auto-remove ''top'' (but it will be removed by a call to ''top'')');

rmdir('.cache', 's');
rmdir('.meta', 's');