% ERROR-HANDLING UNIT TESTS FOR LOADORRUN

%% Put testing files on the path

if ~exist('twoOut', 'file')
    addpath('testing');
end

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
assert(elapsed < .5, 'Cached error lookup should be fast');

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
assert(elapsed < .5, 'Rethrow should be fast');

% 'update' the offending function - this should cause the .error file to be removed in the next
% call.
pause(1);
!touch testing/delayThenError.m

tic;
nil = loadOrRun(@delayThenError, {1, true}, options);  % Failing code should not be called - no try/catch
elapsed = toc;
assert(elapsed >= 1, 'Should have rerun full function');

rmdir('.cache', 's');
rmdir('.meta', 's');