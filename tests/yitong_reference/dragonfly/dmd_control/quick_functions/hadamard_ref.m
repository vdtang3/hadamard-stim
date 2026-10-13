function hadamard_ref(app)

args = app.FunArgsTextArea.Value;

if length(args) < 3
    m_q = [63 14];
else
    m_q = str2num(args{3});
end

cal_file_prefix = args{1};
ref_file_prefix = args{2};


folder = 'E:\';
app.ref_im = dmd_hadamard_reconstruct(app,m_q,folder,cal_file_prefix,ref_file_prefix)';
fig = figure(998);
h_im = findobj(get(fig,'children'),'type','Image');
h_im.CData = app.ref_im;
set(gca,...
    'clim',[prctile(app.ref_im(:),1),prctile(app.ref_im(:),99.95)],...
    'xlim',[1 size(app.ref_im,2)],...
    'ylim',[1 size(app.ref_im,1)])
end