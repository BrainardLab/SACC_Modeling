function [gaborImageObject] = MakeImageSettingsFromPtCld(ptCldObject,screenCalObj,standardGaborCalObject,screenBgExcitations,stimulusN,options)
% Make a gabor image from the point cloud object.
%
% Syntax:
%    [gaborImageObject] = MakeImageSettingsFromPtCld(ptCldObject,screenCalObj,standardGaborCalObject,screenBgExcitations,stimulusN)
%
% Description:
%    This makes a gabor image with a desired contrast using the point cloud
%    method.
%
% Inputs:
%    ptCldObject               - Structure with the contrasts for all
%                                possible settings using the point cloud
%                                method.
%    screenCalObj              - Screen calibration object.
%    standardGaborCalObject    - Structure with the gabor contrasts
%                                and settings in a cal format.
%    screenBgExcitations       - Screen background cone excitations.
%    stimulusN                 - The size of the stimulus (gabor image) in
%                                pixels.
%
% Outputs:
%    gaborImageObject          - Structure with the gabor contrast image in
%                                image format.
%
% Optional key/value pairs:
%    verbose                   - Boolean. Default true. Controls
%                                plotting and printout.
%
% See also:
%    SpectralCalCompute, SpectralCalCheck, SpectralCalAnalyze,
%    SpectralCalISETBio

% History:
%   01/21/22  dhb,gka,smo      - Wrote it.
%   01/24/22  smo              - Made it work.
%   01/31/22  smo              - It is possible to work on multiple
%                                target contrast gabors inside this
%                                function.

%% Set parameters.
arguments
    ptCldObject
    screenCalObj
    standardGaborCalObject
    screenBgExcitations
    stimulusN
    options.verbose (1,1) = true
end

%% Get image from point cloud in cal format.
%
% We want this routine to take contrast explicitly, expressed relative to
% max contrast we set up, when it makes the image.  We will call this
% multiple times to make stimuli of different contrasts.
nContrastPoints = size(standardGaborCalObject.desiredContrastGaborCal,2);

for cc = 1:nContrastPoints
    uniqueQuantizedSettingsGaborCal = SettingsFromPointCloud(ptCldObject.contrastPtCld,standardGaborCalObject.desiredContrastGaborCal{cc},ptCldObject.ptCldSettingsCal);
    
    % Print out min/max of settings
    if (options.verbose)
        fprintf('Gabor image min/max settings: %0.3f, %0.3f\n',min(uniqueQuantizedSettingsGaborCal(:)), max(uniqueQuantizedSettingsGaborCal(:)));
    end
    
    % Get contrasts we think we have obtianed
    uniqueQuantizedExcitationsGaborCal = SettingsToSensor(screenCalObj,uniqueQuantizedSettingsGaborCal);
    uniqueQuantizedContrastGaborCal = ExcitationsToContrast(uniqueQuantizedExcitationsGaborCal,screenBgExcitations);
    
    % Plot of how well point cloud method does in obtaining desired contrats
    if (options.verbose)
        figure; clf;
        plot(ptCldObject.desiredContrastGaborCal(:),uniqueQuantizedContrastGaborCal(:),'r+');
        axis('square');
        xlabel('Desired L, M or S contrast');
        ylabel('Predicted L, M, or S contrast');
        title('Quantized unique point cloud image method');
    end
    
    % Convert representations we want to take forward to image format. Also, save the results in a structure.
    gaborImageObject.uniqueQuantizedContrastGaborImage{cc} = CalFormatToImage(uniqueQuantizedContrastGaborCal,stimulusN,stimulusN);
    gaborImageObject.desiredContrastGaborImage{cc} = CalFormatToImage(standardGaborCalObject.desiredContrastGaborCal{cc},stimulusN,stimulusN);
    gaborImageObject.standardPredictedContrastImage{cc} = CalFormatToImage(standardGaborCalObject.standardPredictedContrastGaborCal{cc},stimulusN,stimulusN);
    gaborImageObject.standardSettingsGaborImage{cc} = CalFormatToImage(standardGaborCalObject.standardSettingsGaborCal{cc},stimulusN,stimulusN);
end

end