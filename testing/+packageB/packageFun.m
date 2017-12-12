function [a, b] = packageFun(a, b, options)
% packageB.packageFun - call @twoOut as a dependency (note that packageA.packageFun has different
% behavior)
[a, b] = loadOrRun(@twoOut, {a, b}, options);
end