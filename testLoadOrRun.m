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

%% Test cache by query struct
q = struct();
q.a = 1;
q.b = 'some text';
q.c = {'foo', 2, 'bar'};
q.d = struct('x', 100, 'y', {{'baz'}});
options = struct('query', q);

expected_query_string = 'a=1-b=some_text-c={foo,2,bar}-d=(x=100-y={baz})';

y1 = loadOrRun(@sin, {pi}, options);
assert(exist(fullfile('.cache', ['sin-' expected_query_string '.mat']), 'file') > 0);

rmdir('.cache', 's');
rmdir('.meta', 's');

%% Test default query
q = struct();
q.a = 1;
q.b = 'some text';
q.c = {'foo', 2, 'bar'};
q.d = struct('x', 100, 'y', {{'baz'}});
dq = q;
options = struct('query', q, 'defaultQuery', dq);
expected_query_string = 'default';
y1 = loadOrRun(@sin, {pi}, options);
assert(exist(fullfile('.cache', ['sin-' expected_query_string '.mat']), 'file') > 0);

q.a = 2;
options = struct('query', q, 'defaultQuery', dq);
expected_query_string = 'a=2';
y1 = loadOrRun(@sin, {pi}, options);
assert(exist(fullfile('.cache', ['sin-' expected_query_string '.mat']), 'file') > 0);

q.a = 1;
q.d = struct('x', 101, 'y', {{'baz'}});
options = struct('query', q, 'defaultQuery', dq);
expected_query_string = 'd=(x=101)';  % Note that d.y is still 'default'
y1 = loadOrRun(@sin, {pi}, options);
assert(exist(fullfile('.cache', ['sin-' expected_query_string '.mat']), 'file') > 0);

rmdir('.cache', 's');
rmdir('.meta', 's');

%% Test 'ignore' fields using empty array in default Query

% Set default query to empty to fully ignore a field
q.a = 1;
q.b = 'some text';
q.c = {'foo', 2, 'bar'};
q.d = struct('x', 100, 'y', {{'baz'}});
dq = q;
dq.a = []; % Always ignore 'a'
options = struct('query', q, 'defaultQuery', dq);
expected_query_string = 'default';
y1 = loadOrRun(@sin, {pi}, options);
assert(exist(fullfile('.cache', ['sin-' expected_query_string '.mat']), 'file') > 0);
options.query.a = 2;
y2 = loadOrRun(@sin, {pi/2}, options);
assert(y1 == y2, 'Since query.a is ignored, y2 should load cached results from y1 even though query.a changed');

% Try ignoring a field in a sub-structure
options.query.d.x = 101;
expected_query_string = 'd=(x=101)';
y3 = loadOrRun(@sin, {options.query.d.x}, options);
assert(exist(fullfile('.cache', ['sin-' expected_query_string '.mat']), 'file') > 0);
options.query.d.x = 102;
options.defaultQuery.d.x = [];
y4 = loadOrRun(@sin, {options.query.d.x}, options);
assert(y4 == y1, 'Since d.x is ignored, y4 should revert to ''default'' value computed in y1');

options.query.d.y = {'foo'};
expected_query_string = 'd=(y={foo})';
y5 = loadOrRun(@sin, {pi/3}, options);
assert(exist(fullfile('.cache', ['sin-' expected_query_string '.mat']), 'file') > 0, 'query.d.x is ignored, but query.d.y should not be affected');
assert(y5 == sin(pi/3));

rmdir('.cache', 's');
rmdir('.meta', 's');

%% Test multiple output args

q = struct();
q.a = 1;
q.b = 1;
options = struct('query', q);
x1 = loadOrRun(@twoOut, {q.a, q.b}, options);
try
    [x1, y1] = loadOrRun(@twoOut, {q.a, q.b}, options);
    assert(false, 'Getting two args after a single arg should fail');
catch
end

q.b = 2;
options.query = q;
[x1, ~] = loadOrRun(@twoOut, {q.a, q.b}, options);
[x1, y1] = loadOrRun(@twoOut, {q.a, q.b}, options);

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

%% Test updated dependency -- call from top

q = struct();
q.val = 1;
options = struct('query', q, 'onDependencyChange', 'warn');
val = loadOrRun(@dependencyTop, {q.val, options}, options);
assert(val == 2);
assert(exist(fullfile('.cache', 'dependencyBottom-val=1.mat'), 'file') > 0);
assert(exist(fullfile('.cache', 'dependencyTop-val=1.mat'), 'file') > 0);

% Modify 'bottom' (update it's timestamp with 'touch')
pause(1);
!touch testing/dependencyBottom.m

sourceInfo = dir(fullfile('testing', 'dependencyBottom.m'));
cacheInfo = dir(fullfile('.cache', 'dependencyBottom-val=1.mat'));
assert(cacheInfo.datenum < sourceInfo.datenum, 'something went wrong with system call ''touch''');

val = loadOrRun(@dependencyTop, {q.val, options}, options);

% Warning should have been issued, and .mat file should NOT have been recomputed
sourceInfo = dir(fullfile('testing', 'dependencyBottom.m'));
cacheInfo = dir(fullfile('.cache', 'dependencyBottom-val=1.mat'));
assert(cacheInfo.datenum < sourceInfo.datenum, 'in ''warn'' mode, dependency change should not trigger an update');

options.onDependencyChange = 'autoremove';
pause(1);
val = loadOrRun(@dependencyTop, {q.val, options}, options);
sourceInfo = dir(fullfile('testing', 'dependencyBottom.m'));
cacheInfoBottom = dir(fullfile('.cache', 'dependencyBottom-val=1.mat'));
assert(cacheInfoBottom.datenum > sourceInfo.datenum, 'in ''autoremove'' mode, dependency change SHOULD trigger an update');
cacheInfoTop = dir(fullfile('.cache', 'dependencyTop-val=1.mat'));
assert(cacheInfoTop.datenum > sourceInfo.datenum, 'in ''autoremove'' mode, dependency change SHOULD trigger an update');

rmdir('.cache', 's');
rmdir('.meta', 's');

%% Test updated dependency -- call from bottom

q = struct();
q.val = 1;
options = struct('query', q, 'onDependencyChange', 'warn');
val = loadOrRun(@dependencyTop, {q.val, options}, options);
assert(val == 2);
assert(exist(fullfile('.cache', 'dependencyBottom-val=1.mat'), 'file') > 0);
assert(exist(fullfile('.cache', 'dependencyTop-val=1.mat'), 'file') > 0);

% Modify 'bottom' (update it's timestamp with 'touch')
pause(1);
!touch testing/dependencyBottom.m

sourceInfo = dir(fullfile('testing', 'dependencyBottom.m'));
cacheInfo = dir(fullfile('.cache', 'dependencyTop-val=1.mat'));
assert(cacheInfo.datenum < sourceInfo.datenum, 'something went wrong with system call ''touch''');

% Directly call bottom of call stack
val = loadOrRun(@dependencyBottom, {q.val}, options);

% Warning should have been issued, and both .mat files should still exist
assert(exist(fullfile('.cache', 'dependencyTop-val=1.mat'), 'file') > 0, 'in ''warn'' mode, dependency change should not trigger an update');
assert(exist(fullfile('.cache', 'dependencyBottom-val=1.mat'), 'file') > 0, 'in ''warn'' mode, dependency change should not trigger an update');

options.onDependencyChange = 'autoremove';
pause(1);
val = loadOrRun(@dependencyBottom, {q.val}, options);
cacheInfo = dir(fullfile('.cache', 'dependencyBottom-val=1.mat'));
assert(cacheInfo.datenum > sourceInfo.datenum, 'in ''autoremove'' mode, cache for ''bottom'' should have been updated!');
assert(exist(fullfile('.cache', 'dependencyTop-val=1.mat'), 'file') > 0, 'expected behavior is that calling ''bottom'' does not auto-remove ''top'' (but it will be removed by a call to ''top'')');

rmdir('.cache', 's');
rmdir('.meta', 's');

%% Test behavior with package functions

val = 7;
options = struct('uid', '12345');

% Test naming conventions for caching package functions
outA = loadOrRun(@packageA.packageFun, {val}, options);
assert(outA == 70);
expected_cache_name = fullfile('.cache', 'packageA.packageFun-12345.mat');
assert(exist(expected_cache_name, 'file') > 0, 'Cache name should include package');
origCacheA = dir(expected_cache_name);

% Test behavior when two packages have a function with the same name
pause(1);
outB = loadOrRun(@packageB.packageFun, {val, val, options}, options);
assert(outB ~= outA, 'Package functions of the same name should not have name collisions - new value should have been computed for packageB.packageFun');
expected_cache_name = fullfile('.cache', 'packageB.packageFun-12345.mat');

% Test 'onDependencyChange' for package functions -- expected behavior is that name collisions cause extra updates.
% Note: packageB.packageFun depends on @twoOut, but packageA.packageFun does not. Because of the name collision, an update to @twoOut should still trigger
% packageA.packageFun to be recomputed
options.onDependencyChange = 'autoremove';
pause(1);
!touch testing/twoOut.m
outA = loadOrRun(@packageA.packageFun, {val * 2}, options);
assert(outA == 140, 'New value should have been computed, triggered by update to packageB''s dependency');
expected_cache_name = fullfile('.cache', 'packageA.packageFun-12345.mat');
newCacheA = dir(expected_cache_name);
assert(newCacheA.datenum > origCacheA.datenum, 'New value should have been computed, triggered by update to packageB''s dependency');

rmdir('.cache', 's');
rmdir('.meta', 's');
