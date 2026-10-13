function [had_all,ref_all] = hadamard_reconstruct(m_q,folder,cal_prefix,ref_prefix,showPinhole,showResults)

    if ~exist('showPinhole','var')
        showPinhole = false;
    end
    if ~exist('showResults','var')
        showResults = false;
    end
    %% construct digital pinhole (scorr) from calibration file(s)
%     cur_dir = pwd;
    
    f_list = ls(fullfile(folder,[ '*' cal_prefix '*']));
    mov_hcal = [];
    for ii = 1:size(f_list,1)
        cur_f = strsplit(f_list(ii,:));
        mov = vm(fullfile(folder,cur_f{1}));
        mov_hcal = cat(4,mov_hcal,mov.data-100);
    end
    
%     multi_file_opt = 'yes';
%     mov_hcal = vm([]);
    n = m_q(1)+1;
    m = m_q(1);
    q = m_q(2);
%     while strcmp(multi_file_opt,'yes')
%         pause(.5)
%         [fname,fpath]=uigetfile(matlabroot,'Please select hadamard calibration sequence','*.bin');
%         [~,~,ext] = fileparts(fname);
%         
%         mov_hcal = vm(cat(4,mov_hcal.data,vm(fpath).data-100));
%         
%         uifig = uifigure;
%         multi_file_opt = uiconfirm(uifig,'Add another calibration file?',...
%             ['current number =' num2str(size(mov_hcal,4))],'options',{'yes','no'},'closeFcn', @(h,e) close(uifig));
%     end
    mov_hcal = vm(sum(mov_hcal,4));
    mov_hcal = vm(single(mean(reshape(mov_hcal.data,mov_hcal.rows,mov_hcal.cols,n,[]),4)));
    
    
    hadtraces = hadamard_bincode_nopermutation(m)'*2-1;
%     hadtraces = hadamard_bincode(m)'*2-1;
    
    ccorr = mov_hcal*hadtraces;
    clear mov_hcal;
    ccorr = (ccorr)./(imgaussfilt(max(abs(ccorr)),1));    
    m = whos('ccorr');
    [userview, systemview] = memory;
    if systemview.PhysicalMemory.Available < m.bytes*16
        error 'not enough memory for Had63c14 calibration'
    end
    
    maxImgSize = 4096;
    ups_n = floor(maxImgSize/max(ccorr.imsz)/2)*2;
%     ups_n = 2;
    ccorr = ccorr.imresize(ups_n,'bilinear');
%     ccorr = ccorr.blur(2).imresize(2,'bilinear');
	% fill upsampled image with pinhole index (3rd dimension)
    ccorr = cat(3,ccorr,-1.*ccorr); 
    [~,ind] = max(ccorr.data,[],3);
	
	% fill pinhole location with 1 or -1 values
    clear ccorr
    rpattern = ones(size(ind));
    rpattern(ind>size(hadtraces,2)) = -1;
	ind(ind>size(hadtraces,2)) = ind(ind>size(hadtraces,2)) - size(hadtraces,2);
    sind = sparse(1:numel(ind),ind,rpattern);
    vmind = vm(full(sind),size(ind));
    clear ind sind mvals
	
	% downsample new pinhole backdown
    scorr = vmind.imresize(1/ups_n,'bilinear');
%     scorr = vmind.imresize(.5,'bilinear').blur(.5);
    clear vmind
    if showPinhole
        figure;moviesc(scorr)
        figure;imshow(scorr.std,[])
    end
	
	% pre-multiply with hadamard code (sample hadamard)
    scorr = scorr*hadtraces';
%     figure;moviesc(scorr)
    %% reconstruct image from Hadamard sequence
%     pause(1)
%     [~,fpath]=uigetfile(matlabroot,'Please select hadamard sequence','*.bin');
    
    f_ref_list = ls(fullfile(folder, ['*' ref_prefix '*']));
    had_all = [];
    ref_all = [];
%     ref_dir = strsplit(f_ref_list);
    for ii = 1:size(f_ref_list,1)
        cur_f = strsplit(f_ref_list(ii,:));
        mov_h = vm(fullfile(folder,cur_f{1}));
%         mov_h= cat(4,mov_h,mov.data-100);
    %     end
    %     mov_h = vm(fullfile(folder,ref_dir{1}));
    %     [mov_h_liveArea,mov_h_offset] = get_mov_ROI(fpath);

        mov_h = mov_h.correct_blank_marker-100;
    %     mov_h_pad = zeros(size(scorr),'uint16');
    %     mov_h_pad(mov_h_offset(2)+1:mov_h_offset(2)+mov_h_liveArea(2),...
    %                 mov_h_offset(1)+1:mov_h_offset(1)+mov_h_liveArea(1),:) = mov_h.data;
    %     mov_h_pad = vm(mov_h_pad);
        ref = mean(mov_h);
    %     had = mean(mov_h_pad.*scorr.ffzpad(mov_h.imsz).blur(1))*2;
        had = zeros(mov_h.imsz);
        for jj = 1:(mov_h.frames/n)
%             had_j = im_lowpass(mean(mov_h((1:n)+(jj-1)*n).*scorr.ffzpad(mov_h.imsz))*2);
            had_j = mean(mov_h((1:n)+(jj-1)*n).*scorr.ffzpad(mov_h.imsz))*2;
            had = had + had_j;
        end
        had = had/n;
        had_all = cat(3,had_all,had);
        ref_all = cat(3,ref_all,ref);
    end
    im = had_all;
    clear mov_h
    if showResults
        figure(58);imshow(ref,[],'initialmagnification','fit');title('Wide Field')
        figure(59);imshow(had,[],'initialmagnification','fit');title('Hadamard')
        figure; moviesc(had_all)
    end
end

function [liveArea,offset] = get_mov_ROI(fpath)
    file_dir = dir(fullfile(fpath,'*set'));
    fid  = fopen(fullfile(file_dir.folder,file_dir.name));
    fline = fgetl(fid);
    txtArray = textscan(fline,'%q');
    while   ~isequal(fline,-1)
            if strcmp(txtArray{1}{1},'-------') || strcmp(txtArray{1}{1},'')
            elseif strcmp(txtArray{1}{2}(1:end-1),'ActiveareaDropDown')
                liveArea = sscanf(txtArray{1}{3},'%f x %f');
            elseif strcmp(txtArray{1}{2}(1:end-1),'OffsetDropDown')
                offset = str2num(txtArray{1}{3});
            end
            fline = fgetl(fid);
            try txtArray = textscan(fline,'%q'); catch,end
    end
    fclose(fid);
end

function im_f = im_lowpass(im_bin)
[nr,nc] = size(im_bin);
fft_im = fftshift(fft2(im_bin));
band_width = round(max(size(im_bin))/4);
f_ker = zeros(size(im_bin));
f_ker(1:band_width,1:band_width)=1;
f_ker(end-band_width:end,1:band_width)=1; 
f_ker(1:band_width,end-band_width:end)=1;
f_ker(end-band_width:end,end-band_width:end)=1;
f_ker = fftshift(f_ker);
im_f = abs(ifft2(ifftshift(fft_im.*imgaussfilt(f_ker,10))));

end