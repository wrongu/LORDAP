function sem = getsemaphore(uid, max_wait_time)
%GETSEMAPHORE create or wait on a semaphore by name. Calls to GETSEMAPHORE with the same UID from
%different processes or instances of matlab will allow only one to run while the others block. Each
%process should get a semaphore, perform *fast* operations, then release it. For example,
%
%     sem = getsemaphore('lock');
%     ... do something quick that must be atomic
%     releasesemaphore(sem);
%
%The UID may also contain a path plus the UID itself to specify the directory where the .sem file(s)
%should be created. For example, if the UID is '/abc/def/xyz/identifier' then the semaphore files
%will look like '/abc/def/xyz/.identifier.672486.sem'
%
% Copyright (c) 2018 Richard Lange
%
% Loosely based on the semaphore functions found here:
% https://www.mathworks.com/matlabcentral/fileexchange/13775-multicore-parallel-processing-on-multiple-cores

% Get time when this function began for checking timeouts and file modification times later.
start_time = tic;

%% Constants and defaults

if ~exist('max_wait_time', 'var'), max_wait_time = 10; end

% All 'datenum' values measure days. There are 86400 seconds per day.
SECS_PER_DAY = 86400;

% If there are errors, old semaphore files may still be around. Delete them if they are older than
% this many seconds:
PROBABLE_ERROR_WAIT_TIME = 30;

% After creating a semaphore file, wait for a moment so that race conditions, if they exist, can
% actually be detected.
FILE_CREATION_PAUSE_TIME_MS = 10;

% If there is a race condition, each process pauses for a random amount of time between 0 and this
% many milliseconds.
RACE_CONDITION_RESTART_MAX_WAIT_MS = 100;

% To distinguish the same UID across different jobs or processes, each generates its own random
% identifier. This constant sets its range. Note the random ID will *not* be sensitive to and will
% not affect the current state of the random number generator, by design.
RANDOM_INDEX_MAX = 1000000;

% If the given UID is too long, it will be shortened. This defines the somewhat arbitrary cutoff
% length. Note that filenames cannot be longer than 255 characters on unix systems, for instance.
MAX_UID_STRING_LENGTH = 200;

% Ensure that UID is a string.
if ~ischar(uid)
    uid = repr(uid);
    path = pwd;
else
    % Extract path part of UID if it exists (but only if it was a string originally)
    [path, name, ext] = fileparts(uid);
    uid = [name ext];
end

% Ensure that UID is not too long by hashing it if it is.
if length(uid) > MAX_UID_STRING_LENGTH, uid = sprintf('%x', string2hash(uid)); end

%% Create helper function to check for existence of other semaphores for this uid

pattern = sprintf('.%s.*.sem', uid);

    function [other_sem_files] = checkOtherSemFiles(ignoreName)
    other_sem_files = dir(fullfile(path, pattern));
    files_to_wait_on = false(size(other_sem_files));
    
    for file_i=1:length(other_sem_files)
        age = (now - other_sem_files(file_i).datenum) * SECS_PER_DAY;
        if age > PROBABLE_ERROR_WAIT_TIME
            warning('MATLAB:getsemaphore:oldfile', 'Found old semaphore file ''%s'' to delete (%ds old).', other_sem_files(file_i).name, round(age));
            releasesemaphore(fullfile(path, other_sem_files(file_i).name));
        elseif ~strcmp(other_sem_files(file_i).name, ignoreName)
            files_to_wait_on(file_i) = true;
        end
    end
    
    other_sem_files = other_sem_files(files_to_wait_on);
    end

%% Loop until timeout or success

timeout = false;
while ~timeout
    %% Always update timing first
    timeout = toc(start_time) > max_wait_time;
    
    %% Each loop, get a fresh list of other semaphore files to wait on, since the list may change each iteration
    other_sem_files = checkOtherSemFiles('');
    
    % Return to the top of the while loop if still waiting on other files.
    if ~isempty(other_sem_files), continue; end

    %% Claim the semaphore by creating a file
    
    my_rand_id = floor(RANDOM_INDEX_MAX * multiprocess_rand);
    my_sem_filename = sprintf('.%s.%d.sem', uid, my_rand_id);
    sem = fullfile(path, my_sem_filename);
    emptyfile(sem);
    
    %% Check for race conditions - other processes may have stopped waiting at the same instant and created their own files
    
    % Give other processes a moment to catch up
    java.lang.Thread.sleep(floor(FILE_CREATION_PAUSE_TIME_MS));
    
    other_sem_files = checkOtherSemFiles(my_sem_filename);
    
    % If in a race condition, pause for a random amount of time.
    if ~isempty(other_sem_files)
        releasesemaphore(sem);
        java.lang.Thread.sleep(floor(multiprocess_rand * RACE_CONDITION_RESTART_MAX_WAIT_MS));
    else
        return;
    end
end

if timeout
    error('MATLAB:getsemaphore:timeout', 'Timed out waiting for semaphore to be released');
end

end