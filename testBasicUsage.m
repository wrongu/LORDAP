% SIMPLE UNIT TESTS FOR LOADORRUN

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
[y1, y2] = loadOrRun(@twoOut, {1, 2}, options);
assert(exist(fullfile('mycache', 'twoOut-12345.mat'), 'file') > 0);
assert(exist(fullfile('mymeta', 'twoOut-sourceDependencies.mat'), 'file') > 0);

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

%% Test 'recompute' flag as boolean

[~, ~] = loadOrRun(@twoOut, {1, 1});
cacheInfo = dir('.cache/twoOut-1-1.mat');

pause(.5);

[~, ~] = loadOrRun(@twoOut, {1, 1});
cacheInfo1 = dir('.cache/twoOut-1-1.mat');

assert(cacheInfo1.datenum == cacheInfo.datenum, 'No modification should have happened yet.');

pause(.5);

options = struct('recompute', true);
[~, ~] = loadOrRun(@twoOut, {1, 1}, options);
cacheInfo2 = dir('.cache/twoOut-1-1.mat');

assert(cacheInfo2.datenum > cacheInfo.datenum, 'Recompute flag should trigger update.');

pause(1);

[~, ~] = loadOrRun(@twoOut, {1, 1}, options);
cacheInfo3 = dir('.cache/twoOut-1-1.mat');

assert(cacheInfo3.datenum > cacheInfo2.datenum, 'Recompute flag should trigger update second time as well.');

rmdir('.cache', 's');
rmdir('.meta', 's');

%% Test 'recompute' flag as timestamp

[~, ~] = loadOrRun(@twoOut, {1, 1});
cacheInfo = dir('.cache/twoOut-1-1.mat');

pause(.5);

[~, ~] = loadOrRun(@twoOut, {1, 1});
cacheInfo1 = dir('.cache/twoOut-1-1.mat');

assert(cacheInfo1.datenum == cacheInfo.datenum, 'No modification should have happened yet.');

% 'now' returns the current time in 'datenum' format.
timecheck = now;

% 'now' and file timestamps differ by fractions of a second. Pause here to not be sensitive to that.
pause(1);

options = struct('recompute', timecheck, 'verbose', 2);
[~, ~] = loadOrRun(@twoOut, {1, 1}, options);
cacheInfo2 = dir('.cache/twoOut-1-1.mat');

assert(cacheInfo2.datenum > cacheInfo.datenum, 'Recompute flag should trigger update.');
assert(cacheInfo2.datenum >= timecheck, 'Timing inconsistency?');

pause(1);

[~, ~] = loadOrRun(@twoOut, {1, 1}, options);
cacheInfo3 = dir('.cache/twoOut-1-1.mat');

assert(cacheInfo3.datenum == cacheInfo2.datenum, ['Second call with flag is not an update, since ' ...
    'the cache file is now newer than ''now'' was before']);

rmdir('.cache', 's');
rmdir('.meta', 's');

%% Test 'dryRun' flag

tstart = tic;
options = struct('dryRun', true);

expected_uid = 'delayThenError-1';

% The function itself will not be run, so (1) it should be fast, and (2) there should be no error.
finfo = loadOrRun(@delayThenError, {1}, options);

assert(strcmp(finfo.uidFinal, expected_uid));

rmdir('.cache', 's');
rmdir('.meta', 's');

%% Test that loading a corrupt file triggers recompute

info = loadOrRun(@twoOut, {1, 2}, struct('dryRun', true));

f = fopen(info.cacheFile, 'w');
fprintf(f, 'this is clearly not a valid matfile\n');
fclose(f);

try
    load(info.cacheFile);
    assert(false, 'Load should fail!');
catch
end

[y1, y2] = loadOrRun(@twoOut, {1, 2}, struct('verbose', 2));

rmdir('.cache', 's');
rmdir('.meta', 's');