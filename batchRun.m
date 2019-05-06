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

% Set up default options.
options = arrayfun(@populateDefaultOptions, options);

c = parcluster;
c.AdditionalProperties.WallTime = time;
c.AdditionalProperties.QueueName = queue;

flags = sprintf('--mem %dGB', ceil(memGB));
if exist('slurmFlags', 'var') && ~isempty(slurmFlags)
    flags = [flags ' ' slurmFlags];
end
c.AdditionalProperties.AdditionalSubmitArgs = flags;

if length(options) == 1
    options = repmat(options, size(argsCell));
end

funcInfo = functions(func);
funcName = funcInfo.function;

jobs = cell(size(argsCell));
jobIds = cell(size(argsCell));
for iJob=1:length(jobs)
    queryOptions = options(iJob);
    queryOptions.dryRun = true;
    info = loadOrRun(func, argsCell{iJob}, queryOptions);
    uid = getOrCreateUID(argsCell{iJob}, options(iJob));
    if info.needsCompute
        jobs{iJob} = c.batch(@loadOrRun, nargout, {func, argsCell{iJob}, options(iJob)});
        jobIds{iJob} = schedID(jobs{iJob});
        if options(iJob).verbose == 1
            fprintf('Submitting job for %s-%s\n', funcName, uid);
        elseif options(iJob).verbose == 2
            fprintf('Submitting job for %s-%s with Job ID %d\n', funcName, uid, jobIds{iJob});
        end
    end
end

if options(1).verbose == 2
    fprintf('STATUSES\n');
    for iJob=1:length(jobs)
        uid = getOrCreateUID(argsCell{iJob}, options(iJob));
        fprintf('%d\t%s\t(%s)\n', jobIds{iJob}, jobs{iJob}.State, uid);
    end
end

end