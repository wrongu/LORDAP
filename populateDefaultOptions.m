function options = populateDefaultOptions(options)

default.cachePath = fullfile(pwd, '.cache');
default.metaPath = fullfile(pwd, '.meta');
default.recompute = false;
default.verbose = false;
default.errorHandling = 'none';
default.numPrecision = 4;
default.onDependencyChange = 'warn';
default.defaultArgs = {};
default.defaultString = 'default';
default.dryRun = false;

extraFields = setdiff(fieldnames(options), [fieldnames(default); {'uid'}]);
if ~isempty(extraFields)
	warning('lordap:options:extraField', 'Options struct contains unrecognized field(s): %s', strjoin(extraFields, ', '));
end

dFields = fieldnames(default);
for iField=1:length(dFields)
	if ~isfield(options, dFields{iField})
		options.(dFields{iField}) = default.(dFields{iField});
	end
end
end