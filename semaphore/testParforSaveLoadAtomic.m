%% Setup

if ~exist('increment', 'file'), addpath('testing'); end

%% Test 1: save/load in parallel fails when not using semaphores

val = 1;
save('testing/data1.mat', 'val');

try
    parfor i=1:100
        increment('testing/data1');
    end
    
    error('this should have failed!');
catch
    % success: an error is expected when increment() is used without semaphores
    delete('testing/data1.mat');
end

%% Test 2: adding semaphores fixes Test 1

val = 1;
save('testing/data2.mat', 'val');

parfor i=1:500
    sem = getsemaphore('data2');
    increment('testing/data2');
    releasesemaphore(sem);
end

contents = load('testing/data2.mat');
assert(contents.val == 501, 'Atomicity is broken - each increment() should have happened serially');

delete('testing/data2.mat');