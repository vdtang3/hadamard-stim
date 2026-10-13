classdef baseWave < matlab.mixin.Copyable
    %baseWave Waveform base class. Provides general waveform operation
    %   methods and properties. 
    %
    %   Waveforms are represented by any combination of defining
    %   parameters. All derived properties can be accessed without storing
    %   underlying waveform matrices. This allows for efficient handling of
    %   large waveforms. Waveforms can be processed with standard math
    %   operations and concatenated. Calibrated waveforms can be defined
    %   using a look-up table.
    %
    %   Methods for class baseWave:
    %     baseWave           
    %     numChannels        
    %     plot               
    %     extend             
    %     copy               
    %     repeat             
    %     repmat             
    %     applyFun           
    %     size               
    %     horzcat            
    %     vertcat            
    %     map                
    %     plus               
    %     uplus
    %     minus              
    %     uminus             
    %     times              
    %     mtimes             
    %     ldivide            
    %     mldivide           
    %     rdivide            
    %     mrdivide           
    %     localGetAmplitude  
    %     localGetTime       
    %     arbWave            
    %
    %   Properties for class baseWave:
    %     dt
    %     nSamples
    %     samplingRate
    %     duration
    %     time
    %     amplitude
    %
    %   See also rampWave, flexRampWave, flexRampTrainWave, arbWave.
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
        dt % these two parameters fully define the timing of a waveform
        nSamples
    end
    properties (Dependent)
        samplingRate % can only be set if dt is empty, updates dt
        duration % can only be set if dt or nSamples is empty, updates the other one
        time % can only be set if both are empty, updates both
        amplitude % should be absent, cannot be set unless overloaded
    end
    methods
        function obj = baseWave(varargin)
            switch nargin
                case 0
                case 1
                    obj.dt = varargin{1};
                case 2
                    obj.dt = varargin{1};
                    obj.duration = varargin{2};
            end
        end
        function value = get.samplingRate(obj)
            if ~isempty(obj.dt)
                value = 1./obj.dt;
            else
                value = [];
            end
        end
        function set.samplingRate(obj,newValue)
            if isempty(obj.dt)
                obj.dt = 1./newValue;
            else
                error('dt must not be set')
            end
        end
        function value = get.duration(obj)
            value = obj.dt*obj.nSamples;
        end
        function set.duration(obj,newValue)
            if isempty(obj.dt) && ~isempty(obj.nSamples)
                obj.dt = newValue./obj.nSamples;
            elseif ~isempty(obj.dt) && isempty(obj.nSamples)
                obj.nSamples = round(newValue./obj.dt);
            else
                error('to set duration, one and only one must be set from {dt, nSamples}')
            end
        end
        function value = get.time(obj)
            value = localGetTime(obj);
        end
        function value = get.amplitude(obj)
            value = localGetAmplitude(obj);
        end
        function value = localGetTime(obj) % method can be overloaded by subclasses
            if ~isempty(obj.dt) && ~isempty(obj.nSamples)
                value = (1:obj.nSamples)*obj.dt;
            else
                value = [];
            end
        end
        function value = localGetAmplitude(obj) % method can be overloaded by subclasses
            value = obj.time*0;
        end
        function set.time(obj,newValue)
            if isempty(obj.dt) && isempty(obj.nSamples)
                if isempty(newValue)
                    obj.dt = [];
                    obj.nSamples = [];
                else
                    obj.nSamples = numel(newValue);
                    obj.dt = newValue(end)./obj.nSamples;
                end
            else
                error('dt and nSamples must not be set')
            end
        end
        function result = uplus(obj)
            result = arbWave;
            result.h_time = obj.time;
            result.h_ampl = uplus(obj.amplitude);
        end
        function result = uminus(obj)
            result = arbWave;
            result.dt = obj.dt;
            result.nSamples = obj.nSamples;
            result.h_ampl = uminus(obj.amplitude);
        end
        function result = plus(obj,operand)
            result = applyFun(obj,operand,@plus);
        end
        function result = minus(obj,operand)
            result = applyFun(obj,operand,@minus);
        end
        function result = times(obj,operand)
            result = applyFun(obj,operand,@times);
        end
        function result = mtimes(obj,operand)
            result = applyFun(obj,operand,@times);
        end
        function result = rdivide(obj,operand)
            result = applyFun(obj,operand,@rdivide);
        end
        function result = ldivide(obj,operand)
            result = applyFun(obj,operand,@ldivide);
        end
        function result = mrdivide(obj,operand)
            result = applyFun(obj,operand,@rdivide);
        end
        function result = mldivide(obj,operand)
            result = applyFun(obj,operand,@ldivide);
        end
        function aW = applyFun(obj,operand,fun)
            if isnumeric(obj)
                sureObj = operand;
            else
                sureObj = obj;
            end
            aW = arbWave;
            aW.dt = sureObj.dt;
            aW.nSamples = sureObj.nSamples;
            aW.h_ampl = fun(safeGetAmplitude(obj),safeGetAmplitude(operand));
            function amp = safeGetAmplitude(questObj)
                if isnumeric(questObj)
                    amp = questObj;
                else
                    amp = questObj.amplitude;
                end
            end
        end
        function n = numChannels(obj)
            n = size(obj.amplitude,1);
        end
        function plot(obj,varargin)
            if isequal(class(obj),'matlab.graphics.axis.Axes')
                hWave = varargin{1};
                plot(obj,hWave.time,hWave.amplitude,varargin{2:end})
            else
                plot(obj.time,obj.amplitude,varargin{:})
            end
        end
        function aW = horzcat(obj,varargin)
            if nargin > 2
                secondObj = horzcat(varargin{1},varargin{2:end});
            elseif nargin > 1
                secondObj = varargin{1};
            else
                aW = obj.copy;
                return
            end
            if isempty(obj)
                aW = secondObj.copy;
            elseif isempty(secondObj)
                aW = obj.copy;
            else
                assert( obj.dt == secondObj.dt , 'waves must have the same dt')
                aW = arbWave;
                aW.dt = obj.dt;
                aW.nSamples = obj.nSamples + secondObj.nSamples;
%                 aW.h_time = [obj.time       secondObj.time+obj.duration];
                aW.h_ampl = [obj.amplitude  secondObj.amplitude];
            end
        end
        function aW = vertcat(obj,varargin)
            if nargin > 2
                secondObj = vertcat(varargin{1},varargin{2:end});
            elseif nargin > 1
                secondObj = varargin{1};
            else
                aW = obj.copy;
                return
            end
            if isempty(obj)
                aW = secondObj.copy;
            elseif isempty(secondObj)
                aW = obj.copy;
            else
                assert( obj.dt == secondObj.dt , 'waves must have the same dt')
                assert( obj.nSamples == secondObj.nSamples , 'waves must have the same duration')
                aW = arbWave;
                aW.dt = obj.dt;
                aW.nSamples = obj.nSamples;
%                 aW.h_time = [obj.time];
                aW.h_ampl = [obj.amplitude; secondObj.amplitude];
            end
        end
        function result = repeat(obj,mn)
            result = obj.repmat([1 mn]);
        end
        function result = repmat(obj,mn)
            if numel(mn)==1
                mn = [mn 1];
            end
            result = obj;
            for it = 2:mn(1)
                result = [result; obj]; %#ok<AGROW>
            end
%             for it = 2:mn(2)
%                 result = [result obj]; %#ok<AGROW>
%             end
            % repmat horz fast
            amp = result.amplitude;
            amp_new = reshape((amp.*ones(mn(2),1))',1,[]);
            if islogical(amp)
                amp_new = logical(amp_new);
            end
            result.h_ampl = amp_new;
            result.nSamples = result.nSamples*mn(2);
            % repmat horz fast end
            

        end
        function aW = extend(obj,duration)
            aW = arbWave; % obj is not an arb wave, we make one
            aW.dt = obj.dt;
            if mod(duration,aW.dt)
                warning('duration %g rounded to %g',duration,round(duration/aW.dt)*aW.dt)
            end
            aW.duration = round(duration/aW.dt)*aW.dt;
%             aW.h_time = (1:aW.nSamples)*aW.dt;
            temp = obj.amplitude;
            if size(temp,2) > aW.nSamples
                temp(:,aW.nSamples+1:end) = [];
            else
                temp(:,aW.nSamples) = 0;
            end
            aW.h_ampl = temp;
        end
        function aW = arbWave(obj)
            aW = arbWave; % obj is not an arb wave, we make one
            aW.dt = obj.dt;
            aW.duration = obj.duration;
%             aW.h_time = obj.time;
            aW.h_ampl = obj.amplitude;
        end
        function newObj = map(obj,fun)
%             newObj = arbWave(obj.time,obj.amplitude);
            newObj = arbWave(obj);
            newObj.h_ampl = fun(newObj.h_ampl);
        end
        function varargout = size(obj,varargin)
            switch nargout
                case 0
                    varargout = {size(obj.time,varargin{:})};
                otherwise
                    eval(['[' sprintf('v%d, ',1:nargout) '] = size(obj.amplitude,varargin{:});'])
                    varargout = eval(['{' sprintf('v%d, ',1:nargout) '}']);
            end
        end
    end
end

