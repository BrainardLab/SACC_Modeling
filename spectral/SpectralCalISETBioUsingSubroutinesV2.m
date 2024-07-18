% SpectralCalISETBioUsingSubroutinesV2
%
% Description:
%    Illustrate how to set up ISETBio based stimuli for the projector.
%    This version illustrates use of our encapsulated functions.
%
%    See SpectralCalCompute etc. (see "See also" list below) for a more
%    elaborated version of this the underlying computations.
%
% See also: SpectralCalCompute, SpectralCalCheck, SpectralCalAnalyze,
%           SpectralCalISETBio

% History:
%    01/18/22  dhb,smo    Started on it.
%    01/26/22  smo        It is working well with the substituting
%                         functions!
%    04/15/22  smo        Corrections because of the sub routines now
%                         save the variables in cell format.
%    10/18/22  smo        Updated it to use to check calibration every
%                         time we make test images for the experiment.

%% Clear.
clear; close all;

%% Set key stimulus parameters.
%
% Set up color direction parameters by its condition name.
conditionName = 'LminusMSmooth';

% Set priamry and gabor image contrast settings.
targetScreenPrimaryContrast = 0.07;
spatialGaborTargetContrast = 0.07;
targetLambda = 3;

% Set up color direction here.
colorDirectionParams = SetupColorDirection(conditionName,...
    'targetScreenPrimaryContrasts',targetScreenPrimaryContrast,...
    'spatialGaborTargetContrast',spatialGaborTargetContrast,...
    'targetLambda',targetLambda);

% Set to true to get more output.
VERBOSE = true;
lightVer = false;
printGaborSpds = true;

%% Do all calibraiton loading.
screenGammaMethod = 2;
[screenCalObj,channelCalObjs] = LoadAndSetExperimentCalFiles(colorDirectionParams,'screenGammaMethod',screenGammaMethod,'verbose',VERBOSE);

%% Image spatial parameters.
%
% Image will be centered in display.
sineFreqCyclesPerDeg = 1;
gaborSdDeg = 0.75;
stimulusSizeDeg = 7;

%% Use extant machinery to get primaries from spectrum.
%
% Define wavelength range that will be used to enforce the smoothness
% through the projection onto an underlying basis set.  We don't the whole
% visible spectrum as putting weights on the extrema where people are not
% sensitive costs us smoothness in the spectral region we care most about.
lowProjectWl = 400;
highProjectWl = 700;
projectIndices = find(colorDirectionParams.wls > lowProjectWl & colorDirectionParams.wls < highProjectWl);

%% Find primaries with desired LMS contrast.
[screenPrimaryChannelObject,backgroundChannelObject] = SetupChannelPrimaries(colorDirectionParams,channelCalObjs,projectIndices,'verbose',VERBOSE);

%% Set the screen primaries.
%
% We want these to match those we set up with the channel calculations
% above.  Need to reset sensor color space after we do this, so that the
% conversion matrix is properly recomputed.
screenCalObj.set('P_device', screenPrimaryChannelObject.screenPrimarySpd);
SetSensorColorSpace(screenCalObj, colorDirectionParams.T_cones, colorDirectionParams.S);

%% Create ISETBio display from the calibration file.
[ISETBioDisplayObject,screenSizeObject,screenCalObjFromISETBio] = SetupISETBioDisplayObject(colorDirectionParams,screenCalObj,'verbose',VERBOSE);

%% Set up the background screen primaries.
backgroundScreenPrimaryObject = SetupBackground(colorDirectionParams,screenCalObj,backgroundChannelObject,'verbose',VERBOSE);

%% Make a monochrome Gabor patch in range -1 to 1.
%
% This is our monochrome contrast modulation image. Multiply by the max
% contrast vector to get the LMS contrast image. The function includes the
% quantization of the gabor image.
nQuantizeBits = 14;
[rawMonochromeUnquantizedContrastGaborImage, rawMonochromeUnquantizedContrastGaborCal, rawMonochromeContrastGaborCal, ...
    stimulusN, centerN, stimulusHorizSizeDeg, stimulusHorizSizeMeters] = ...
    MakeMonochromeContrastGabor(stimulusSizeDeg,sineFreqCyclesPerDeg,gaborSdDeg,screenSizeObject,'verbose',VERBOSE,'nQuantizeBits',nQuantizeBits);

%% Get cone contrast/excitation gabor image.
[ptCldObject,standardGaborCalObject] = SetupPointCloudFromGabor(colorDirectionParams,rawMonochromeContrastGaborCal,...
    screenCalObj,backgroundScreenPrimaryObject,screenPrimaryChannelObject,'verbose',VERBOSE,'lightVer',lightVer,'printGaborSpds',printGaborSpds);

%% Make image from point cloud.
gaborImageObject = MakeImageSettingsFromPtCld(ptCldObject,screenCalObj,standardGaborCalObject,...
    backgroundScreenPrimaryObject.screenBgExcitations,stimulusN,'verbose',VERBOSE,'lightVer',lightVer);

%% Put the image into an ISETBio scene.
ISETBioGaborObject = MakeISETBioSceneFromImage(colorDirectionParams,gaborImageObject,standardGaborCalObject,...
    ISETBioDisplayObject,stimulusHorizSizeMeters,stimulusHorizSizeDeg,'verbose',VERBOSE);

% Go back to the RGB image starting with the ISETBio representation.
fromISETBioGaborCalObject = GetSettingsFromISETBioScene(screenCalObjFromISETBio,ISETBioGaborObject,standardGaborCalObject,'verbose',VERBOSE);

%% SRGB image via XYZ, scaled to display
predictedXYZCal = colorDirectionParams.T_xyz * cell2mat(standardGaborCalObject.desiredSpdGaborCal);
SRGBPrimaryCal = XYZToSRGBPrimary(predictedXYZCal);
scaleFactor = max(SRGBPrimaryCal(:));
SRGBCal = SRGBGammaCorrect(SRGBPrimaryCal/(2*scaleFactor),0);
SRGBImage = uint8(CalFormatToImage(SRGBCal,stimulusN,stimulusN));

% Show the SRGB image
figure; imshow(SRGBImage);
title('SRGB Gabor Image');

%% Show the settings image.
figure; clf;
figurePosition = [0 0 1000 500];
set(gcf,'position',figurePosition);

% Standard method.
subplot(1,2,1);
imshow(cell2mat(gaborImageObject.standardSettingsGaborImage));
title('Standard method');

% Point cloud method.
subplot(1,2,2);
imshow(cell2mat(gaborImageObject.uniqueQuantizedSettingsGaborImage));
title('Point cloud method');

%% Plot slice through predicted LMS contrast image.
%
% Set the plot limit axis.
plotAxisLimit = 100 * colorDirectionParams.spatialGaborTargetContrast;

% SensorToSettings method.
PlotSliceContrastGaborImage(cell2mat(gaborImageObject.standardPredictedContrastImage), cell2mat(gaborImageObject.desiredContrastGaborImage),...
    'plotAxisLimit', plotAxisLimit, 'verbose', VERBOSE);
if (screenGammaMethod == 2)
    title('Image Slice, SensorToSettings Method, Quantized Gamma, LMS Cone Contrast');
else
    title('Image Slice, SensorToSettings Method, No Quantization, LMS Cone Contrast');
end

% Point cloud method.
PlotSliceContrastGaborImage(cell2mat(gaborImageObject.uniqueQuantizedContrastGaborImage), cell2mat(gaborImageObject.desiredContrastGaborImage),...
    'plotAxisLimit', plotAxisLimit, 'verbose', VERBOSE);
title('Image Slice, Point Cloud Method, LMS Cone Contrast');

%% Generate some settings values corresponding to known contrasts
%
% The reason for this is to measure and check these.  This logic follows
% how we handled an actual gabor image above. We don't actually need to
% quantize to 14 bits here on the contrast, but nor does it hurt.
nQuantizeLevels = 2^nQuantizeBits;
rawMonochromeUnquantizedContrastCheckCal = [0 0.05 -0.05 0.10 -0.10 0.15 -0.15 0.20 -0.20 0.25 -0.25 0.5 -0.5 1 -1];
rawMonochromeContrastCheckCal = 2*(PrimariesToIntegerPrimaries((rawMonochromeUnquantizedContrastCheckCal+1)/2,nQuantizeLevels)/(nQuantizeLevels-1))-1;
desiredContrastCheckCal = colorDirectionParams.spatialGaborTargetContrast * colorDirectionParams.targetStimulusContrastDir * rawMonochromeContrastCheckCal;
desiredExcitationsCheckCal = ContrastToExcitation(desiredContrastCheckCal,backgroundScreenPrimaryObject.screenBgExcitations);

% For each check calibration find the settings that come as close as
% possible to producing the desired excitations.
%
% If we measure for a uniform field the spectra corresopnding to each of
% the settings in the columns of ptCldScreenSettingsCheckCall, then compute
% the cone contrasts with respect to the backgound (0 contrast measurement,
% first settings), we should approximate the cone contrasts in
% desiredContrastCheckCal.
ptCldScreenSettingsCheckCal = SettingsFromPointCloud(ptCldObject.contrastPtCld,desiredContrastCheckCal,ptCldObject.ptCldSettingsCal);
ptCldScreenPrimariesCheckCal = SettingsToPrimary(screenCalObj,ptCldScreenSettingsCheckCal);
ptCldScreenSpdCheckCal = PrimaryToSpd(screenCalObj,ptCldScreenPrimariesCheckCal);
ptCldScreenExcitationsCheckCal = SettingsToSensor(screenCalObj,ptCldScreenSettingsCheckCal);
ptCldScreenContrastCheckCal = ExcitationsToContrast(ptCldScreenExcitationsCheckCal, backgroundScreenPrimaryObject.screenBgExcitations);
figure; clf; hold on;
plot(desiredContrastCheckCal(:),ptCldScreenContrastCheckCal(:),'ro','MarkerSize',10,'MarkerFaceColor','r');
xlim([0 plotAxisLimit/100]); ylim([0 plotAxisLimit/100]); axis('square');
xlabel('Desired'); ylabel('Obtained');
title('Check of desired versus obtained check contrasts');

% Check that we can recover the settings from the spectral power
% distributions, etc.  This won't necessarily work perfectly, but should be
% OK.
for tt = 1:size(ptCldScreenSettingsCheckCal,2)
    ptCldPrimariesFromSpdCheckCal(:,tt) = SpdToPrimary(screenCalObj,ptCldScreenSpdCheckCal(:,tt),'lambda',0);
    ptCldSettingsFromSpdCheckCal(:,tt) = PrimaryToSettings(screenCalObj,ptCldScreenSettingsCheckCal(:,tt));
end
figure; clf; hold on
plot(ptCldScreenSettingsCheckCal(:),ptCldSettingsFromSpdCheckCal(:),'+','MarkerSize',12);
xlim([0 1]); ylim([0 1]);
xlabel('Computed primaries'); ylabel('Check primaries from spd'); axis('square');

% Make sure that screenPrimarySettings leads to screenPrimarySpd
clear screenPrimarySpdCheck
for pp = 1:length(channelCalObjs)
    screenPrimarySpdCheck(:,pp) = PrimaryToSpd(channelCalObjs{pp},SettingsToPrimary(channelCalObjs{pp}, screenPrimaryChannelObject.screenPrimarySettings(:,pp)));
end
figure; clf; hold on
plot(colorDirectionParams.wls, screenPrimarySpdCheck,'k','LineWidth',4);
plot(colorDirectionParams.wls, screenPrimaryChannelObject.screenPrimarySpd,'r','LineWidth',2);
xlabel('Wavelength'); ylabel('Radiance');
title('Check of consistency between screen primaries and screen primary spds');

%% Save out what we need to check things on the DLP
%
% For now, we read out variables from objects to save so that we can utilize
% the other codes, SpectralCalCheck and SpectralCalAnalyze, without changing
% the variables in the codes (as of 04/18/22).
S = colorDirectionParams.S;
T_cones = colorDirectionParams.T_cones;
screenNInputLevels = colorDirectionParams.screenNInputLevels;
targetStimulusContrastDir = colorDirectionParams.targetStimulusContrastDir;
spatialGaborTargetContrast = colorDirectionParams.spatialGaborTargetContrast; 

screenSettingsImage = gaborImageObject.standardSettingsGaborImage;

screenPrimaryPrimaries = screenPrimaryChannelObject.screenPrimaryPrimaries;
screenPrimarySettings = screenPrimaryChannelObject.screenPrimarySettings;
screenPrimarySpd = screenPrimaryChannelObject.screenPrimarySpd;

if (ispref('SpatioSpectralStimulator','SCMDData'))
    testFiledir = getpref('SpatioSpectralStimulator','SCMDData');
    testFilename = fullfile(testFiledir,'CheckCalibration','testImageData');
    save(testFilename,'S','T_cones','screenCalObj','channelCalObjs','screenSettingsImage', ...
        'screenPrimaryPrimaries','screenPrimarySettings','screenPrimarySpd',...
        'desiredContrastCheckCal','rawMonochromeUnquantizedContrastCheckCal', ...
        'ptCldScreenSettingsCheckCal','ptCldScreenContrastCheckCal','ptCldScreenSpdCheckCal', ...
        'nQuantizeLevels','screenNInputLevels','targetStimulusContrastDir','spatialGaborTargetContrast',...
        'targetScreenPrimaryContrast','targetLambda');
end
