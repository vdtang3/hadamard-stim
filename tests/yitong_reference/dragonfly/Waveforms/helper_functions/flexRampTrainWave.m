classdef flexRampTrainWave < flexRampWave
    %flexRampTrainWave Flexible ramp train waveform. Adds periodic
    %   repetition to ramp waveforms.
    %
    %   Waveforms are represented by any combination of defining
    %   parameters. All derived properties can be accessed without storing
    %   underlying waveform matrices. This allows for efficient handling of
    %   large waveforms. Waveforms can be processed with standard math
    %   operations and concatenated. Calibrated waveforms can be defined
    %   using a look-up table.
    %
    %   Methods for class flexRampTrainWave:
    %     flexRampTrainWave
    %       plus all methods inherited from flexRampWave
    %
    %   Properties for class flexRampTrainWave:
    %     period
    %     frequency
    %     phase
    %     dc
    %       plus all properties inherited from flexRampWave
    %
    %   See also baseWave, rampWave, flexRampWave, arbWave.
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
        period
    end
    properties (Dependent)
        frequency
        phase
        dc
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
            obj.initialAmp = 1;
        end
        function value = get.frequency(obj)
            value = 1./obj.period;
        end
        function set.frequency(obj,newValue)
            obj.period = 1./newValue;
        end
        function value = get.phase(obj)
            value = obj.tBefore./obj.period;
        end
        function set.phase(obj,newValue)
            obj.tBefore = obj.period.*newValue;
        end
        function value = get.dc(obj)
            value = obj.tRamp./obj.period;
        end
        function set.dc(obj,newValue)
            obj.tRamp = obj.period.*newValue;
        end
        function value = localGettAfter(obj)
            value = obj.period - obj.tBefore - obj.tRamp;
        end
        function localSettAfter(obj,newAfter)
            if    ( ~isempty(obj.tBefore) + ...
                    ~isempty(obj.tRamp) + ...
                    ~isempty(obj.period) ) == 2
                if isempty(obj.tBefore)
                    obj.tBefore = obj.period - obj.tRamp - newAfter;
                elseif isempty(obj.tRamp)
                    obj.tRamp = obj.period - obj.tBefore - newAfter;
                else % duration is empty
                    obj.period = obj.tBefore + obj.tRamp + newAfter;
                end
            else
                error('to set tAfter, two and only two must be set from {tBefore, tRamp, duration}')
            end
        end
        function value = localGetAmplitude(obj)
            if ...
                    ~isempty(obj.tRamp) && ...
                    ~isempty(obj.initialHeight) && ...
                    ~isempty(obj.finalHeight) && ...
                    ~isempty(obj.offset)
                localTime = obj.time;
                localTime = (localTime./obj.period-ceil(localTime./obj.period)+1)*obj.period;
                value = (localTime-obj.tBefore)./obj.tRamp;
                value = value .* (obj.finalHeight-obj.initialHeight)+obj.initialHeight;
                value = value .* (obj.tBefore < localTime & localTime <= (obj.tBefore+obj.tRamp));
                value = value + obj.offset;
            else
                error('waveform paremters underdetermined')
            end
        end
        
    end
end