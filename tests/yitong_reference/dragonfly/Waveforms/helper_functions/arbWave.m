classdef arbWave < baseWave
    %arbWave Arbitrary waveform. This class encapsulates a dense
    %   matrix representation of waveforms, usually as a final container
    %   for waveforms bwfore otuput. Operations are defined by baseWave.
    %
    %   Waveforms are represented by any combination of defining
    %   parameters. All derived properties can be accessed without storing
    %   underlying waveform matrices. This allows for efficient handling of
    %   large waveforms. Waveforms can be processed with standard math
    %   operations and concatenated. Calibrated waveforms can be defined
    %   using a look-up table.
    %
    %   Methods for class arbWave:
    %     advanceRisingEdges
    %       plus all methods inherited from baseWave
    %
    %   Properties for class arbWave are the same as for baseWave. More
    %   elaborate defining parameters are lost. 
    %
    %   See also baseWave, rampWave, flexRampWave, flexRampTrainWave.
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

    properties (Hidden)
        h_ampl = [];
    end
    methods
        function value = localGetAmplitude(obj) % method can be overloaded by subclasses
%             if isa(obj.h_ampl,'uint32')
%                 value = [];
%                 for it = 1:size(obj.h_ampl,1)
%                     value = [value; rle_decode(obj.h_ampl(:,it))'];
%                 end
%             else
                value = obj.h_ampl;
%             end
        end
        function set.h_ampl(obj,value)
%             if isequal(value,logical(value)) && isequal(value(:,1),false(size(value(:,1))))
%                 obj.h_ampl = [];
%                 for it = 1:size(value,1)
%                     obj.h_ampl = [obj.h_ampl; rle_encode(value(it,:))'];
%                 end
% 
            if isequal(value,logical(value))
                obj.h_ampl = logical(value);
            else
                obj.h_ampl = value;
            end
        end
        function obj = arbWave(varargin)
            switch nargin
                case 1 
                    obj = arbWave;
                    obj.dt = varargin{1}.dt;
                    obj.duration = varargin{1}.duration;
                    obj.h_ampl = varargin{1}.amplitude;
                case 2
                    error 'obsolete due to roundoff errors. use arbWave() instead.'
%                     time = varargin{1};
%                     ampl = varargin{2};
%                     assert(isequal(size(time,2),size(ampl,2)),'time and amplitude must have the same length')
%                     obj.nSamples = numel(time);
%                     obj.dt = mean(diff(time(:)));
%                     obj.h_time = time;
%                     obj.h_ampl = ampl;
            end
        end
        function obj = advanceRisingEdges(obj,offset)
            assert(isequal(obj.h_ampl,logical(obj.h_ampl)),'free amplitude waveforms not supported');
            if mod(offset,obj.dt)
                warning('offset %g rounded to %g',offset,round(offset/obj.dt)*obj.dt)
            end
            nadv = round(offset/obj.dt);
            obj.h_ampl = imdilate(obj.h_ampl,[ones(1,nadv) 1 zeros(1,nadv)]);
        end
    end
end