function nil = delayThenError(delayAmount, skipError)
% Helper function for testing
pause(delayAmount);

% Call to surf with no arguments triggers an error.
if nargin < 2 || ~skipError
    surf;
else
    nil = 0;
end
end