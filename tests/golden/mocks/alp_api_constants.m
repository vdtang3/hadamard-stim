function api = alp_api_constants()
%ALP_API_CONSTANTS The ALP constants Yitong's DMD code reads from obj.api.
%   Values are copied from Luminos's bundled alp.h
%   (src/lib/Luminos_MEX_VS/DMD/alp.h), so a recorded call log uses the same
%   numbers the Luminos MEX will send.
api.DEFAULT = 0;
api.NOT_ONLINE = 1001;
api.PROJ_MODE = 2300;
api.MASTER = 2301;
api.SLAVE_VD = 2302;               % ALP_SLAVE_VD is defined as ALP_SLAVE
api.PROJ_QUEUE_MODE = 2314;
api.PROJ_LEGACY = 0;
api.PROJ_SEQUENCE_QUEUE = 1;
api.PROJ_QUEUE_MAX_AVAIL = 2316;
api.PROJ_QUEUE_AVAIL = 2317;
api.DATA_FORMAT = 2110;
api.DATA_BINARY_TOPDOWN = 2;
api.SEQ_REPEAT = 2100;
api.BIN_MODE = 2104;
api.BIN_UNINTERRUPTED = 2106;
api.PICTURE_TIME = 2203;
api.ILLUMINATE_TIME = 2204;
end
