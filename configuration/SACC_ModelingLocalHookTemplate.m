function SACC_ModelingLocalHook
% SACC_Modeling
%
% Configure things for working on the SACC_Modeling project.
%
% For use with the ToolboxToolbox.  If you copy this into your
% ToolboxToolbox localToolboxHooks directory (by default,
% ~/localToolboxHooks) and delete "LocalHooksTemplate" from the filename,
% this will get run when you execute tbUseProject('ColorMaterial') to set up for
% this project.  You then edit your local copy to match your configuration.
%
% You will need to edit the project location and i/o directory locations
% to match what is true on your computer.

%% Define project
projectName = 'SACC_Modeling';

%% Say hello
fprintf('Running %s local hook\n',projectName);

%% Clear out old preferences
if (ispref(projectName))
    rmpref(projectName);
end

%% Specify project location
projectBaseDir = tbLocateProject(projectName);

% If we ever needed some user/machine specific preferences, this is one way
% we could do that.
sysInfo = GetComputerInfo();
switch (sysInfo.localHostName)
    otherwise
        % Some unspecified machine, try user specific customization
        switch(sysInfo.userShortName)
            % Could put user specific things in, but at the moment generic
            % is good enough.
     
            case 'colorlab'
                % SACCSFA desktop (Linux)
                userNameDropbox = 'Mela Nopsin';
                baseDir = fullfile('/home/',sysInfo.userShortName,'Aguirre-Brainard Lab Dropbox',userNameDropbox);
                
            otherwise
                if ismac
                    dbJsonConfigFile = '~/.dropbox/info.json';
                    fid = fopen(dbJsonConfigFile);
                    raw = fread(fid,inf);
                    str = char(raw');
                    fclose(fid);
                    val = jsondecode(str);
                    baseDir = val.business.path;
                end
        end
end

%% Project prefs
setpref(projectName,'LEDSpectraDir',fullfile(baseDir,'SCMD_materials','JandJProjector','LEDSpectrumMeasurements'));

% Calibration
setpref('BrainardLabToolbox','CalDataFolder',fullfile(baseDir,'SCMD_materials','Calibration'));

% Main experiment data dir (as of 10/14/22)
setpref(projectName,'SCMDData',fullfile(baseDir,'SCMD_data'));

% Check data dir (This is for screen stability and channel additivity data)
setpref(projectName,'CheckDataFolder',fullfile(baseDir,'SCMD_materials','JandJProjector','CheckData'));

% SCMD materials.
setpref(projectName,'SCMDMaterials',fullfile(baseDir,'SCMD_materials'));

% We will save the final results in this directory (as of 10/13/23).
setpref(projectName,'SCMDAnalysis',fullfile(baseDir,'SCMD_analysis'));



