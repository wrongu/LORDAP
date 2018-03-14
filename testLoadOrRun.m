% UNIT TESTS FOR LOADORRUN

%% Put testing files on the path

if ~exist('twoOut', 'file')
    addpath('testing');
end

%% Test cache by UID

options = struct('uid', '12345');
y1 = loadOrRun(@sin, {pi}, options);
assert(exist(fullfile('.cache', 'sin-12345.mat'), 'file') > 0);

y2 = loadOrRun(@sin, {pi/2}, options);
assert(y2 == sin(pi) && y1 == y2, 'Because of same uid, y2 should equal y1');

options = struct('uid', 'abcde');
y2 = loadOrRun(@sin, {pi/2}, options);
assert(y2 == sin(pi/2), 'New uid should compute a new value for y2');

assert(exist(fullfile('.cache', 'sin-abcde.mat'), 'file') > 0);

rmdir('.cache', 's');
rmdir('.meta', 's');

%% Test custom output directory

options = struct('uid', '12345', 'cachePath', 'mycache', 'metaPath', 'mymeta');
y1 = loadOrRun(@sin, {pi}, options);
assert(exist(fullfile('mycache', 'sin-12345.mat'), 'file') > 0);
assert(exist(fullfile('mymeta', 'dependencies.mat'), 'file') > 0);

rmdir('mycache', 's');
rmdir('mymeta', 's');

%% Test basic cache-by-args

args = {12, true, 'foo bar', struct('a', 1, 'b', {{'c', 'd'}}), {'baz', pi}};
expected_uid = '12-T-foo_bar-(a=1-b={c-d})-{baz-3.142}';

val = loadOrRun(@funcWithManyArgs, args);
assert(val == 12);
assert(exist(fullfile('.cache', ['funcWithManyArgs-' expected_uid '.mat']), 'file') > 0);

rmdir('.cache', 's');
rmdir('.meta', 's');

%% Test basic default args

args = {12, true, 'foo bar baz', struct('a', 1, 'b', {{'c', 'd'}}), {'baz', pi}};
options = struct('defaultArgs', {args});
args{2} = false;
expected_uid = '12-F-default-default-default';
val = loadOrRun(@funcWithManyArgs, args, options);
assert(val == -12);
assert(exist(fullfile('.cache', ['funcWithManyArgs-' expected_uid '.mat']), 'file') > 0);

% Change 'default' to 'xx' in cache file names
args{1} = 13;
args{2} = true;
options.defaultString = 'xx';
expected_uid = '13-T-xx-xx-xx';
val = loadOrRun(@funcWithManyArgs, args, options);
assert(val == 13);
assert(exist(fullfile('.cache', ['funcWithManyArgs-' expected_uid '.mat']), 'file') > 0);

% Test all-default
args{1} = 12;
options.defaultArgs = args;
expected_uid = 'xx';
val = loadOrRun(@funcWithManyArgs, args, options);
assert(val == 12);
assert(exist(fullfile('.cache', ['funcWithManyArgs-' expected_uid '.mat']), 'file') > 0);

rmdir('.cache', 's');
rmdir('.meta', 's');

%% Test recursive default args in a struct

args = {12, true, 'foo bar', struct('a', 1, 'b', {{'c', 'd'}}), {'baz', pi}};
options = struct('defaultArgs', {args});
args{4} = struct('a', 2, 'b', {{'c', 'd'}});
% Note the absence of 'b=default'; structs only include non-default fields.
expected_uid = '12-T-foo_bar-(a=2)-default';
val = loadOrRun(@funcWithManyArgs, args, options);
assert(val == 12);
assert(exist(fullfile('.cache', ['funcWithManyArgs-' expected_uid '.mat']), 'file') > 0);

rmdir('.cache', 's');
rmdir('.meta', 's');

%% Test recursive default args in a cell array

args = {12, true, 'foo bar', struct('a', 1, 'b', {{'c', 'd'}}), {'baz', pi}};
options = struct('defaultArgs', {args});
args{5} = {'baz', 0};
expected_uid = '12-T-foo_bar-default-{baz-0}';  % 'baz' is too short to be replaced with 'default'
val = loadOrRun(@funcWithManyArgs, args, options);
assert(val == 12);
assert(exist(fullfile('.cache', ['funcWithManyArgs-' expected_uid '.mat']), 'file') > 0);

options.defaultString = 'X';
expected_uid = '12-T-X-X-{X-0}';  % all strings shorter than 'X' are now replaced with 'X'
val = loadOrRun(@funcWithManyArgs, args, options);
assert(val == 12);
assert(exist(fullfile('.cache', ['funcWithManyArgs-' expected_uid '.mat']), 'file') > 0);

rmdir('.cache', 's');
rmdir('.meta', 's');

%% Test string name of objects

m1 = MyObject(1,2);
expected_uid = '(val1=1-val2=2)'; % object fields converted to struct
val = loadOrRun(@fnOnObject, {m1});
assert(val == 3);
assert(exist(fullfile('.cache', ['fnOnObject-' expected_uid '.mat']), 'file') > 0);

m1.val1 = 0;
expected_uid = '(val1=0-val2=2)'; % object fields converted to struct
val = loadOrRun(@fnOnObject, {m1});
assert(val == 2);
assert(exist(fullfile('.cache', ['fnOnObject-' expected_uid '.mat']), 'file') > 0);

rmdir('.cache', 's');
rmdir('.meta', 's');

%% Test equality of objects

m1 = MyObject(1,2);
mdefault = {MyObject(1,2)};
options = struct('defaultArgs', {mdefault});
expected_uid = 'default';
val = loadOrRun(@fnOnObject, {m1}, options);
assert(val == 3);
assert(exist(fullfile('.cache', ['fnOnObject-' expected_uid '.mat']), 'file') > 0);

m1.val1 = 0;
options = struct('defaultArgs', {mdefault});
expected_uid = '(val1=0)'; % if just val2 is default, only val1 enters the string
val = loadOrRun(@fnOnObject, {m1}, options);
assert(val == 2);
assert(exist(fullfile('.cache', ['fnOnObject-' expected_uid '.mat']), 'file') > 0);

rmdir('.cache', 's');
rmdir('.meta', 's');

%% Test basic ignore args with default set to []

args = {12, true, 'foo bar baz', struct('a', 1, 'b', {{'c', 'd'}}), {'baz', pi}};
expected_uid = '12-default-(a=1-b={c-d})-{baz-3.142}';
options = struct('defaultArgs', {{12, [], 'foo bar baz'}});
val = loadOrRun(@funcWithManyArgs, args, options);
assert(val == 12);
assert(exist(fullfile('.cache', ['funcWithManyArgs-' expected_uid '.mat']), 'file') > 0);
% Changing an ignored value should have no effect - previous cached result is loaded
args{2} = false;
val2 = loadOrRun(@funcWithManyArgs, args, options);
assert(val2 == val);

rmdir('.cache', 's');
rmdir('.meta', 's');

%% Test recursive ignore args in a struct

args = {10, true, 'foo bar', struct('a', 1, 'b', {{'c', 'd'}}), {'baz', pi}};
options = struct('defaultArgs', {args});
options.defaultArgs{4} = struct('a', 1, 'b', []); % ignore b but not a
args{4}.a = 100;
args{4}.b = {'x', 'y', 'z'}; % ignored
expected_uid = '10-T-foo_bar-(a=100)-default';
val = loadOrRun(@funcWithManyArgs, args, options);
assert(val == 10);
assert(exist(fullfile('.cache', ['funcWithManyArgs-' expected_uid '.mat']), 'file') > 0);

args{4}.b = {1, 2, 3, 4}; % still ignored
expected_uid = '10-T-foo_bar-(a=100)-default';
val = loadOrRun(@funcWithManyArgs, args, options);
assert(val == 10);
assert(exist(fullfile('.cache', ['funcWithManyArgs-' expected_uid '.mat']), 'file') > 0);

args{1} = 11;
args{4}.a = 2;
expected_uid = '11-T-foo_bar-(a=2)-default';
val = loadOrRun(@funcWithManyArgs, args, options);
assert(val == 11);
assert(exist(fullfile('.cache', ['funcWithManyArgs-' expected_uid '.mat']), 'file') > 0);

rmdir('.cache', 's');
rmdir('.meta', 's');

%% Test recursive ignore args in a cell array

args = {100, true, 'foo bar', struct('a', 1, 'b', {{'c', 'd'}}), {'baz', pi}};
options = struct('defaultArgs', {args});
options.defaultArgs{5} = {[], pi}; % ignore 1st element of cell array but not 2nd
args{5} = {'fizz', 'buzz', 0, 1, 2};
expected_uid = '100-T-foo_bar-default-{buzz-0-1-2}'; % fizz is ignored
val = loadOrRun(@funcWithManyArgs, args, options);
assert(val == 100);
assert(exist(fullfile('.cache', ['funcWithManyArgs-' expected_uid '.mat']), 'file') > 0);

rmdir('.cache', 's');
rmdir('.meta', 's');

%% Test multiple output args

x1 = loadOrRun(@twoOut, {1, 1});
assert(x1 == 2);
try
    [x1, y1] = loadOrRun(@twoOut, {q.a, q.b});
    assert(false, 'Getting two args after a single arg should fail');
catch
end

[x1, ~] = loadOrRun(@twoOut, {1, 2});
assert(x1 == 3);
[x1, y1] = loadOrRun(@twoOut, {1, 2});
assert(x1 == 3);
assert(y1 == -1);

try
    loadOrRun(@twoOut, {1, 2});
    assert(false, 'Calling without outputs after caching with outputs should fail');
catch
end

rmdir('.cache', 's');
rmdir('.meta', 's');

%% Test error handling

options = struct('uid', '12345', 'errorHandling', 'none');
tic;
try
    nil = loadOrRun(@delayThenError, {1}, options);
    assert(false, 'should have failed!');
catch
end
elapsed = toc;
assert(elapsed >= 1, 'Full function not completed before error');

tic;
try
    nil = loadOrRun(@delayThenError, {1}, options);
    assert(false, 'should have failed!');
catch
end
elapsed = toc;
assert(elapsed >= 1, 'Full function not completed before error');

options.errorHandling = 'cache';
tic;
try
    nil = loadOrRun(@delayThenError, {1}, options);
    assert(false, 'should have failed!');
catch
end
elapsed = toc;
assert(elapsed < .1, 'Cached error lookup should be fast');

rmdir('.cache', 's');
rmdir('.meta', 's');

%% Test that errors are not rethrown when dependencies are updated

options = struct('uid', '12345', 'errorHandling', 'cache', 'onDependencyChange', 'autoremove');
tic;
try
    nil = loadOrRun(@delayThenError, {1}, options);
    assert(false, 'should have failed!');
catch
end
elapsed = toc;
assert(elapsed >= 1, 'Full function not completed before error');

tic;
try
    nil = loadOrRun(@delayThenError, {1, true}, options);
    assert(false, 'Should rethrow cached error since uid is the same');
catch
end
elapsed = toc;
assert(elapsed < .1, 'Rethrow should be fast');

% 'update' the offending function - this should cause the .error file to be removed in the next
% call.
pause(1);
!touch testing/delayThenError.m

tic;
nil = loadOrRun(@delayThenError, {1, true}, options);  % Failing code should not be called - no try/catch
elapsed = toc;
assert(elapsed >= 1, 'Should have rerun full function');

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

%% Test behavior with package functions

val = 7;
options = struct('uid', '12345');

% Test naming conventions for caching package functions
outA = loadOrRun(@packageA.packageFun, {val}, options);
assert(outA == 10 * val);
expected_cache_name = fullfile('.cache', 'packageA.packageFun-12345.mat');
assert(exist(expected_cache_name, 'file') > 0, 'Cache name should include packageA');
origCacheA = dir(expected_cache_name);

% Test behavior when two packages have a function with the same name
pause(.1);
outB = loadOrRun(@packageB.packageFun, {val, val, options}, options);
assert(outB ~= outA, 'Package functions of the same name should not have name collisions - new value should have been computed for packageB.packageFun');
expected_cache_name = fullfile('.cache', 'packageB.packageFun-12345.mat');
assert(exist(expected_cache_name, 'file') > 0, 'Cache name should include packageB');

% Test 'onDependencyChange' for package functions -- expected behavior is that name collisions cause
% extra updates since packageA.packageFun and packageB.packageFun are combined into a single
% 'packageFun' entry in the dependencies table.
% Note: packageB.packageFun depends on @twoOut, but packageA.packageFun does not. Because of the
% name collision, an update to @twoOut should still trigger packageA.packageFun to be recomputed
options.onDependencyChange = 'autoremove';
pause(1);
!touch testing/twoOut.m
outA = loadOrRun(@packageA.packageFun, {val * 2}, options);
assert(outA == 10 * val * 2, 'New value should have been computed, triggered by update to packageB''s dependency');
expected_cache_name = fullfile('.cache', 'packageA.packageFun-12345.mat');
newCacheA = dir(expected_cache_name);
assert(newCacheA.datenum > origCacheA.datenum, 'New value should have been computed, triggered by update to packageB''s dependency');

rmdir('.cache', 's');
rmdir('.meta', 's');
