classdef flexRampWave < rampWave % (InferiorClasses = {?baseWave}) 
    %flexRampWave Flexible ramp waveform. Adds detailed amplitude control
    %   to ramp waveforms. Flat ramps also serve as square waves. 
    %
    %   Waveforms are represented by any combination of defining
    %   parameters. All derived properties can be accessed without storing
    %   underlying waveform matrices. This allows for efficient handling of
    %   large waveforms. Waveforms can be processed with standard math
    %   operations and concatenated. Calibrated waveforms can be defined
    %   using a look-up table.
    %
    %   Methods for class flexRampWave:
    %     flexRampWave
    %       plus all methods inherited from rampWave
    %
    %   Properties for class flexRampWave:
    %     offset
    %     initialHeight
    %     finalHeight
    %     baseAmp
    %     initialAmp
    %     finalAmp
    %       plus all properties inherited from rampWave
    %
    %   See also baseWave, rampWave, flexRampTrainWave, arbWave.
    %
    %   2018-2019 Vicente Parot
    %   Cohen Lab - Harvard university
    
% % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % %
% 
%   Copyright 2018-2019 Vicente Parot
% 
%   Permission is hereby granted, free of charge, to any person obtaining a
%   copy of this software and associated documentation files (the
%   "Software"), to deal in the Software without restriction, including
%   without limitation the rights to use, copy, modify, merge, publish,
%   distribute, sublicense, and/or sell copies of the Software, and to
%   permit persons to whom the Software is furnished to do so, subject to
%   the following conditions:
% 
%   The above copyright notice and this permission notice shall be included
%   in all copies or substantial portions of the Software. 
% 
%   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
%   OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
%   MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
%   IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
%   CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
%   TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
%   SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
%
% % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % %

    properties
        offset = 0; 
        initialHeight = 0;
        finalHeight = 1;
    end
    properties (Dependent)
        baseAmp = 0;
        initialAmp = 0;
        finalAmp = 1;
    end
    methods
        function obj = flexRampWave(varargin)
            switch nargin
                case 0
                case 1
                    obj.dt = varargin{1};
                case 2
                    obj.dt = varargin{1};
                    obj.duration = varargin{2};
            end
        end
        function value = get.baseAmp(obj)
            value = obj.offset;
        end
        function set.baseAmp(obj,newValue)
            obj.offset = newValue;
        end
        function value = get.initialAmp(obj)
            value = obj.offset + obj.initialHeight;
        end
        function set.initialAmp(obj,newValue)
            obj.initialHeight = newValue - obj.offset;
        end
        function value = get.finalAmp(obj)
            value = obj.offset + obj.finalHeight;
        end
        function set.finalAmp(obj,newValue)
            obj.finalHeight = newValue - obj.offset;
        end
        function value = localGetAmplitude(obj)
            if ...
                    ~isempty(obj.tRamp) && ...
                    ~isempty(obj.initialHeight) && ...
                    ~isempty(obj.finalHeight) && ...
                    ~isempty(obj.offset)
                value = (obj.time-obj.tBefore)./obj.tRamp;
                value = value .* (obj.finalHeight-obj.initialHeight)+obj.initialHeight;
                value = value .* (obj.tBefore < obj.time & obj.time <= (obj.tBefore+obj.tRamp));
                value = value + obj.offset;
            else
                error('waveform paremters underdetermined')
            end
        end
    end
end