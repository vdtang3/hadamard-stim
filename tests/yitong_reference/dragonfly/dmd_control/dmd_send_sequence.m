function dmd_send_sequence(app)

pat = app.mask_sequence;

alp_patterns = alp_logical_to_btd(permute(pat,[2 1 3]));

app.dmd.load_sequence(alp_patterns);