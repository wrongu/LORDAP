% PARALLELIZATION TESTS

%% Put testing files on the path

if ~exist('twoOut', 'file')
    addpath('testing');
end

%% Try the same function/args combination in multiple parallel loops

parfor i=1:50
    [y1, y2] = loadOrRun(@twoOut, {1, 2});
end

% Run the same loop a second time - previous versions would run once but fail on the second try

parfor i=1:50
    [y1, y2] = loadOrRun(@twoOut, {1, 2});
end

% check that semaphores were properly cleaned up
assert(isempty(dir('.meta/*.sem')));
