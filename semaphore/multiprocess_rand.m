function n = multiprocess_rand(varargin)
%MULTIPROCESS_RAND a wrapper around rand that deliberately gives different values in different
%processes/machines even if their rng seed is the same.
%
%Copyright (c) 2018 Richard Lange
%
%Loosely based on code found in the multicore package here:
% https://www.mathworks.com/matlabcentral/fileexchange/13775-multicore-parallel-processing-on-multiple-cores

% See here: http://undocumentedmatlab.com/blog/undocumented-feature-function
process_host_string = java.lang.management.ManagementFactory.getRuntimeMXBean.getName.char;
process_host_num = string2hash(process_host_string);

% Create a seed based on the current process (different across parfor loops), host machine
% environment (potentially different across machines in a cluster), and the current time.
seed = mod(floor(process_host_num + cputime * 1000 + now * 86400), 2^32);

% Store rng state, get new random number, then restore rng state.
state = rng;
rng(seed, 'twister');
n = rand(varargin{:});
rng(state);

end