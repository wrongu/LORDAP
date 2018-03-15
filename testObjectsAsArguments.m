% OBJECT UNIT TESTS FOR LOADORRUN

%% Put testing files on the path

if ~exist('twoOut', 'file')
    addpath('testing');
end

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