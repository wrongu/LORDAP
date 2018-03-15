% PACKAGE FUNCTIONS UNIT TESTS FOR LOADORRUN

%% Put testing files on the path

if ~exist('twoOut', 'file')
    addpath('testing');
end

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