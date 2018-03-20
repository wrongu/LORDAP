function val = increment(filename)
% This is not safe to do in a parfor, since multiple processes cannot read/write the same .mat file.
% Further, this allows the atomicity of this semaphore system to be tested by checking that the
% number of calls to increment matches the final value saved in data.mat

contents = load(filename);
val = contents.val + 1;
save(filename, 'val');

end