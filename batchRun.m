function [jobs, jobIds] = batchRun(func, nargout, argsCell, options, time, queue, memGB, slurmFlags)
% BATCHRUN precompute and cache loadOrRun(func, args, options) results as batch jobs on a cluster
% (assuming the SLURM scheduler)
%
% [jobs, jobIds] = BATCHRUN(func, nargout, argsCell, options, time, queue, memGB) repeatedly calls
% loadOrRun(func, argsCell{i}, options), once for each set of arguments in argsCell. Must also supply
% 'time' in the SLURM format (i.e. 'hh:mm:ss' or 'd-hh:mm:ss'), the queue or partition name (e.g. 
% 'short'), and the amount of memory per job in GB. Returns a cell array of jobs returned by
% `parcluster.batch` and a cell array of numeric jobIds
%
% BATCHRUN(..., slurmFlags) can be used to specify additional flags like stdout and stderr files
% (e.g. slurmFlags could be '-o myjob.out.%J.txt -e myjob.err.%J.txt', where SLURM itself will
% replace '%J' with the job id)

ClusterInfo.setWallTime(time);
ClusterInfo.setQueueName(queue);
ClusterInfo.setMemUsage(sprintf('%dGB', ceil(memGB))));
if exist('slurmFlags', 'var') && ~isempty(slurmFlags), ClusterInfo.setUserDefinedOptions(slurmFlags); end
c = parcluster;

jobs = cell(size(argsCell));
jobIds = cell(size(argsCell));
for iJob=1:length(jobs)
    jobs{iJob} = c.batch(@loadOrRun, nargout, {func, argsCell{iJob}, options});
    jobIds{iJob} = schedID(jobs{iJob});
end

end