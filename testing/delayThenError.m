function nil = delayThenError(delayAmount)
% Helper function for testing
pause(delayAmount);

% Call to surf with no arguments triggers an error.
surf;
end