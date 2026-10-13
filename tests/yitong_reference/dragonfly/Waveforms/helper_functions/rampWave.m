classdef rampWave < baseWave % (InferiorClasses = {?baseWave}) 
    %rampWave Ramp waveform. The ramp is characterized by a time before,
    %   during, and after the ramp.
    %
    %   Waveforms are represented by any combination of defining
    %   parameters. All derived properties can be accessed without storing
    %   underlying waveform matrices. This allows for efficient handling of
    %   large waveforms. Waveforms can be processed with standard math
    %   operations and concatenated. Calibrated waveforms can be defined
    %   using a look-up table.
    %
    %   Methods for class rampWave:
    %     rampWave
    %     flexRampTrainWave
    %     localGettAfter
    %     localSettAfter
    %       plus all methods inherited from baseWave
    %
    %   Properties for class rampWave:
    %     tBefore
    %     tRamp
    %     tAfter
    %       plus all properties inherited from baseWave
    %
    %   See also baseWave, flexRampWave, flexRampTrainWave, arbWave.
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
        tBefore = 0;
        tRamp
    end
    properties (Dependent)
        tAfter
    end
    methods
        function obj = flexRampTrainWave(varargin)
            switch nargin
                case 0
                case 1
                    obj.dt = varargin{1};
                case 2
                    obj.dt = varargin{1};
                    obj.duration = varargin{2};
            end
        end
        function value = get.tAfter(obj)
            value = localGettAfter(obj);
        end
        function value = localGettAfter(obj)
            value = obj.duration - obj.tBefore - obj.tRamp;
        end
        function set.tAfter(obj,newAfter)
            localSettAfter(obj,newAfter);
        end
        function localSettAfter(obj,newAfter)
            if    ( ~isempty(obj.tBefore) + ...
                    ~isempty(obj.tRamp) + ...
                    ~isempty(obj.duration) ) == 2
                if isempty(obj.tBefore)
                    obj.tBefore = obj.duration - obj.tRamp - newAfter;
                elseif isempty(obj.tRamp)
                    obj.tRamp = obj.duration - obj.tBefore - newAfter;
                else % duration is empty
                    obj.duration = obj.tBefore + obj.tRamp + newAfter;
                end
            else
                error('to set tAfter, two and only two must be set from {tBefore, tRamp, duration}')
            end
        end
        function value = localGetAmplitude(obj)
            if ~isempty(obj.tRamp)
                value = (obj.time-obj.tBefore)./obj.tRamp;
                value = value .* (obj.tBefore < obj.time & obj.time <= (obj.tBefore+obj.tRamp));
            else
                error('waveform paremters underdetermined')
            end
        end
    end
end