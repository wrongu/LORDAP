function s = releasesemaphore(sem)
%RELEASESEMAPHORE release the semaphore file indicated by 'sem'. This function must be called after
%sem=SETSEMAPHORE(...).
%
%For example,
%
%     sem = getsemaphore('lock');
%     ... do something quick that must be atomic
%     releasesemaphore(sem);

if exist(sem, 'file')
    delete(sem);
    s = 0;
else
    s = -1;
end

end