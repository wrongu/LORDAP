classdef MyObject
    properties
        val1
        val2
    end
    
    methods
        % Constructor
        function obj = MyObject(v1, v2)
        obj.val1 = v1;
        obj.val2 = v2;
        end
        
        % Dummy method
        function t = add(obj)
        t = obj.val1 + obj.val2;
        end
    end
    
end
