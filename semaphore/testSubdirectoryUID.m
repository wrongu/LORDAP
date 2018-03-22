%% Setup

if ~exist('increment', 'file'), addpath('testing'); end

%% Test 1: UID contains the testing directory

val = 1;
save('testing/data3.mat', 'val');

parfor i=1:100
    sem = getsemaphore('testing/data3');
    increment('testing/data3');
    releasesemaphore(sem);
end

contents = load('testing/data3.mat');
assert(contents.val == 101, 'Atomicity is broken - each increment() should have happened serially');

delete('testing/data3.mat');