% SpectralCalCompute
%
% Explore spectral fits with subprimaries, this
% version using the calibration structures.
%

% History:
%    04/22/2020  Started on it.

%% Clear
clear; close all;

%% Decide which mode to test.
%
% Set it either 'normal' or 'high'.
testImageContrast = 'high';

%% Verbose?
%
% Set to true to get more output
VERBOSE = false;

% Set wavelength support.
%
% This needs to match what's in the calibration files, but
% we need it before we read those files.  A mismatch will
% throw an error below.
S = [380 2 201];

%% Set key stimulus parameters
%
% Condition Name.
conditionName = 'MelDirected1';
switch (conditionName)
    case 'MelDirected1'
        % Background xy.
        %
        % Specify the chromaticity, but we'll chose the luminance based
        % on the range available in the device.
        targetBgxy = [0.3127 0.3290]';

        % Target color direction and max contrasts.
        %
        % This is the basic desired modulation direction positive excursion. We go
        % equally in positive and negative directions.  Make this unit vector
        % length, as that is good convention for contrast.
        targetStimulusContrastDir = [0 0 0 1]'; targetStimulusContrastDir = targetStimulusContrastDir/norm(targetStimulusContrastDir);

        % Specify desired primary properties.
        %
        % These are the target contrasts for the three primaries. We want these to
        % span a triangle around the line specified above. Here we define that
        % triangle by hand.  May need a little fussing for other directions, and
        % might be able to autocompute good choices.
        targetScreenPrimaryContrastDir(:,1) = [0 0 0 1]'; targetScreenPrimaryContrastDir(:,1) = targetScreenPrimaryContrastDir(:,1)/norm(targetScreenPrimaryContrastDir(:,1));
        targetScreenPrimaryContrastDir(:,2) = [-0.5 -0.5   1 -1]'; targetScreenPrimaryContrastDir(:,2) = targetScreenPrimaryContrastDir(:,2)/norm(targetScreenPrimaryContrastDir(:,2));
        targetScreenPrimaryContrastDir(:,3) = [ 0.5  0.5  -1 -1]'; targetScreenPrimaryContrastDir(:,3) = targetScreenPrimaryContrastDir(:,3)/norm(targetScreenPrimaryContrastDir(:,3));

        % Set parameters for getting desired target primaries.
        switch testImageContrast
            case 'normal'
                targetScreenPrimaryContrast = 0.05;
            case 'high'
                targetScreenPrimaryContrast = 0.15;
        end
        targetScreenPrimaryContrasts = ones(1,4) * targetScreenPrimaryContrast;
        targetPrimaryHeadroom = 1.05;
        primaryHeadroom = 0;

        % We may not need the whole direction contrast excursion. Specify max
        % contrast we want relative to that direction vector.
        % The first number is
        % the amount we want to use, the second has a little headroom so we don't
        % run into numerical error at the edges. The second number is used when
        % defining the three primaries, the first when computing desired weights on
        % the primaries.
        switch testImageContrast
            case 'normal'
                spatialGaborTargetContrast = 0.10;
            case 'high'
                spatialGaborTargetContrast = 0.15;
        end
        plotAxisLimit = 100*spatialGaborTargetContrast;
        
        % Set up basis to try to keep spectra close to.
        %
        % This is how we enforce a smoothness or other constraint
        % on the spectra.  What happens in the routine that finds
        % primaries is that there is a weighted error term that tries to
        % maximize the projection onto a passed basis set.
        basisType = 'fourier';
        nFourierBases = 13;
        switch (basisType)
            case 'cieday'
                load B_cieday
                B_naturalRaw = SplineSpd(S_cieday,B_cieday,S);
            case 'fourier'
                B_naturalRaw = MakeFourierBasis(S,nFourierBases);
            otherwise
                error('Unknown basis set specified');
        end
        B_natural{1} = B_naturalRaw;
        B_natural{2} = B_naturalRaw;
        B_natural{3} = B_naturalRaw;
end

%% Define calibration filenames/params.
%
% This is a standard calibration file for the DLP screen,
% with the subprimaries set to something.  As we'll see below,
% we're going to rewrite those.nPrimaries
screenCalName = 'SACC';
screenNInputLevels = 256;

% These are the calibration files for each of the primaries, which
% then entails measuring the spectra of all the subprimaries for that
% primary.
channelCalNames = {'SACCPrimary1' 'SACCPrimary2' 'SACCPrimary3'};
channelNInputLevels = 253;

%% Load screen calibration and refit its gamma
screenCal = LoadCalFile(screenCalName);
screenCalObj = ObjectToHandleCalOrCalStruct(screenCal);
gammaMethod = 'identity';
screenCalObj.set('gamma.fitType',gammaMethod);
CalibrateFitGamma(screenCalObj, screenNInputLevels);

%% Load channel calibrations.
nScreenPrimaries = 3;
channelCals = cell(nScreenPrimaries ,1);
channelCalObjs = cell(nScreenPrimaries ,1);
for cc = 1:length(channelCalNames)
    channelCals{cc} = LoadCalFile(channelCalNames{cc});
    channelCalObjs{cc} = ObjectToHandleCalOrCalStruct(channelCals{cc});
    CalibrateFitGamma(channelCalObjs{cc}, channelNInputLevels);
end

%% Get out some data to work with.
%
% This is from the channel calibration file.
Scheck = channelCalObjs{1}.get('S');
if (any(S ~= Scheck))
    error('Mismatch between calibration file S and that specified at top');
end
wls = SToWls(S);
nChannels = channelCalObjs{1}.get('nDevices');

%% Cone fundamentals, mel fundamental, and XYZ CMFs.
psiParamsStruct.coneParams = DefaultConeParams('cie_asano');
psiParamsStruct.coneParams.fieldSizeDegrees = 10;
T_cones = ComputeObserverFundamentals(psiParamsStruct.coneParams,S);
T_mel = GetHumanPhotoreceptorSS(S, {'Melanopsin'}, psiParamsStruct.coneParams.fieldSizeDegrees, psiParamsStruct.coneParams.ageYears,...
    psiParamsStruct.coneParams.pupilDiamMM);
T_receptors = [T_cones ; T_mel];

% XYZ
load T_xyzJuddVos % Judd-Vos XYZ Color matching function
T_xyz = SplineCmf(S_xyzJuddVos,683*T_xyzJuddVos,S);

%% Image spatial parameters.
sineFreqCyclesPerImage = 6;
gaborSdImageFraction = 0.1;

% Image size in pixels
imageN = 512;

%% Get half on spectrum.
%
% This is useful for scaling things reasonably - we start with half of the
% available range of the primaries.
halfOnChannels = 0.5*ones(nChannels,1);
halfOnSpd = PrimaryToSpd(channelCalObjs{1},halfOnChannels);

%% Use quantized conversion?
%
% Comment in the line that refits the gamma to see
% effects of extreme quantization one what follows.
channelGammaMethod = 2;
SetGammaMethod(channelCalObjs{1},channelGammaMethod);
SetGammaMethod(channelCalObjs{2},channelGammaMethod);
SetGammaMethod(channelCalObjs{3},channelGammaMethod);

% Define wavelength range that will be used to enforce the smoothnes
% through the projection onto an underlying basis set.  We don't the whole
% visible spectrum as putting weights on the extrema where people are not
% sensitive costs us smoothness in the spectral region we care most about.
lowProjectWl = 400;
highProjectWl = 700;
projectIndices = find(wls > lowProjectWl & wls < highProjectWl);

% Target lambda determines how heavily the smoothness constraint is weighed
% in the optimization.  Bigger weighs smoothness more heavily.  This
% parameter thus trades off contrast accuracy against smoothness.  We used 
% 3 in our initial computations, which had a target primary contrast of
% 0.05 and a maximum gabor contrast of 0.04.  But this is too large when we
% push to 0.08/0.07.  A value of 1 is OK for that case, and 2 too big.  Not
% sure where in between we can set and still get good contrast accuracy.
%
% You can also reduce smoothness by increasing the number of Fourier basis
% functions defining the smoothness constraint.
switch testImageContrast
    case 'normal'
        targetLambda = 3;     
    case 'high'
        targetLambda = 0.2;
end

% Adjust these to keep background in gamut
primaryBackgroundScaleFactor = 0.5;
screenBackgroundScaleFactor = 0.5;

% Make a loop for getting background for all primaries.
% Passing true for key 'Scale' causes these to be scaled reasonably
% relative to gamut, which is why we can set the target luminance
% arbitrarily to 1 just above. The scale factor determines where in the
% approximate channel gamut we aim the background at.
targetBackgroundPrimaryVal = 0.5;
for pp = 1:nScreenPrimaries
    channelBackgroundPrimaries(:,pp) = targetBackgroundPrimaryVal*ones(size(halfOnChannels));
    channelBackgroundSpd(:,pp) = PrimaryToSpd(channelCalObjs{pp},channelBackgroundPrimaries(:,pp));
    channelBackgroundXYZ(:,pp) = T_xyz*channelBackgroundSpd(:,pp);
end
if (any(channelBackgroundPrimaries < 0) | any(channelBackgroundPrimaries > 1))
    error('Oops - primaries should always be between 0 and 1');
end
fprintf('Background primary min: %0.2f, max: %0.2f, mean: %0.2f\n', ...
    min(channelBackgroundPrimaries(:)),max(channelBackgroundPrimaries(:)),mean(channelBackgroundPrimaries(:)));

% maxBackgroundPrimary = 0.4;
% backgroundPrimaryFactor = maxBackgroundPrimary/max(channelBackgroundPrimaries(:));
% channelBackgroundPrimaries = backgroundPrimaryFactor*channelBackgroundPrimaries;
% channelBackgroundSpd = backgroundPrimaryFactor*channelBackgroundSpd;
% channelBackgroundXYZ = backgroundPrimaryFactor*channelBackgroundXYZ;
% fprintf('Adjusted background primary min: %0.2f, max: %0.2f, mean: %0.2f\n', ...
%     min(channelBackgroundPrimaries(:)),max(channelBackgroundPrimaries(:)),mean(channelBackgroundPrimaries(:)));

%% Find primaries with desired LMS contrast.
%
% Get isolating primaries for all screen primaries.
for pp = 1:nScreenPrimaries
    % The ambient with respect to which we compute contrast is from all
    % three primaries, which we handle via the extraAmbientSpd key-value
    % pair in the call.  The extra is for the primaries not being found in
    % the current call - the contribution from the current primary is known
    % because we pass the primaries for the background.
    otherPrimaries = setdiff(1:nScreenPrimaries,pp);
    extraAmbientSpd = 0;
    for oo = 1:length(otherPrimaries)
        extraAmbientSpd = extraAmbientSpd + channelBackgroundSpd(:,otherPrimaries(oo));
    end

    % Get isolating screen primaries.
    [screenPrimaryPrimaries(:,pp),screenPrimaryPrimariesQuantized(:,pp),screenPrimarySpd(:,pp),screenPrimaryContrast(:,pp),screenPrimaryModulationPrimaries(:,pp)] ... 
        = FindChannelPrimaries(targetScreenPrimaryContrastDir(:,pp), ...
        targetPrimaryHeadroom,targetScreenPrimaryContrasts(pp),channelBackgroundPrimaries(:,pp), ...
        T_receptors,channelCalObjs{pp},B_natural{pp},projectIndices,primaryHeadroom,targetLambda,'ExtraAmbientSpd',extraAmbientSpd);
    
    % We can wonder about how close to gamut our primaries are.  Compute
    % that here.
    primaryGamutScaleFactor(pp) = MaximizeGamutContrast(screenPrimaryModulationPrimaries(:,pp),channelBackgroundPrimaries(:,pp));
    fprintf('\tPrimary %d, gamut scale factor is %0.3f\n',pp,primaryGamutScaleFactor(pp));
    
    % Find the channel settings that correspond to the desired screen
    % primaries.
    screenPrimarySettings(:,pp) = PrimaryToSettings(channelCalObjs{pp},screenPrimaryPrimaries(:,pp));
end

%% How close are spectra to subspace defined by basis?
isolatingNaturalApproxSpd1 = B_natural{1}*(B_natural{1}(projectIndices,:)\screenPrimarySpd(projectIndices,1));
isolatingNaturalApproxSpd2 = B_natural{2}*(B_natural{2}(projectIndices,:)\screenPrimarySpd(projectIndices,2));
isolatingNaturalApproxSpd3 = B_natural{3}*(B_natural{3}(projectIndices,:)\screenPrimarySpd(projectIndices,3));

% Plot of the screen primary spectra.
subplot(2,2,1); hold on
plot(wls,screenPrimarySpd(:,1),'b','LineWidth',2);
plot(wls,isolatingNaturalApproxSpd1,'r:','LineWidth',1);
plot(wls(projectIndices),screenPrimarySpd(projectIndices,1),'b','LineWidth',4);
plot(wls(projectIndices),isolatingNaturalApproxSpd1(projectIndices),'r:','LineWidth',3);
xlabel('Wavelength (nm)'); ylabel('Power (arb units)');
title('Primary 1');

subplot(2,2,2); hold on
plot(wls,screenPrimarySpd(:,2),'b','LineWidth',2);
plot(wls,isolatingNaturalApproxSpd2,'r:','LineWidth',1);
plot(wls(projectIndices),screenPrimarySpd(projectIndices,2),'b','LineWidth',4);
plot(wls(projectIndices),isolatingNaturalApproxSpd2(projectIndices),'r:','LineWidth',3);
xlabel('Wavelength (nm)'); ylabel('Power (arb units)');
title('Primary 2');

subplot(2,2,3); hold on
plot(wls,screenPrimarySpd(:,3),'b','LineWidth',2);
plot(wls,isolatingNaturalApproxSpd3,'r:','LineWidth',1);
plot(wls(projectIndices),screenPrimarySpd(projectIndices,3),'b','LineWidth',4);
plot(wls(projectIndices),isolatingNaturalApproxSpd3(projectIndices),'r:','LineWidth',3);
xlabel('Wavelength (nm)'); ylabel('Power (arb units)');
title('Primary 3');

%% Set the screen primaries.
%
% We want these to match those we set up with the
% channel calculations above.  Need to reset
% sensor color space after we do this, so that the
% conversion matrix is properly recomputed.
screenCalObj.set('P_device',screenPrimarySpd);
SetSensorColorSpace(screenCalObj,T_receptors,S);

%% Set screen gamma method.
%
% If we set to 0, there is no quantization and the result is excellent.
% If we set to 2, this is quantized at 256 levels and the result is more
% of a mess.  The choice of 2 represents what we think will actually happen
% since the real device is quantized.
%
% The point cloud method below reduces this problem.
screenGammaMethod = 2;
SetGammaMethod(screenCalObj,screenGammaMethod);

%% Set up desired background.
%
% We aim for the background that we said we wanted when we built the screen primaries.
desiredBgExcitations = screenBackgroundScaleFactor*T_receptors*sum(channelBackgroundSpd,2);
screenBgSettings = SensorToSettings(screenCalObj,desiredBgExcitations);
screenBgExcitations = SettingsToSensor(screenCalObj,screenBgSettings);
figure; clf; hold on;
plot(desiredBgExcitations,screenBgExcitations,'ro','MarkerFaceColor','r','MarkerSize',12);
axis('square');
xlim([min([desiredBgExcitations ; screenBgExcitations]),max([desiredBgExcitations ; screenBgExcitations])]);
ylim([min([desiredBgExcitations ; screenBgExcitations]),max([desiredBgExcitations ; screenBgExcitations])]);
xlabel('Desired bg excitations'); ylabel('Obtained bg excitations');
title('Check that we obtrain desired background excitations');
fprintf('Screen settings to obtain background: %0.2f, %0.2f, %0.2f\n', ...
    screenBgSettings(1),screenBgSettings(2),screenBgSettings(3));

%% What is the contrast of the primaries with respect to he actual background?

%% Make monochrome Gabor patch in range -1 to 1.
%
% This is our monochrome contrast modulation image.  Multiply
% by the max contrast vector to get the LMS contrast image.
fprintf('Making Gabor contrast image\n');
centerN = imageN/2;
gaborSdPixels = gaborSdImageFraction*imageN;
rawMonochromeSineImage = MakeSineImage(0,sineFreqCyclesPerImage,imageN);
gaussianWindow = normpdf(MakeRadiusMat(imageN,imageN,centerN,centerN),0,gaborSdPixels);
gaussianWindow = gaussianWindow/max(gaussianWindow(:));
rawMonochromeUnquantizedContrastGaborImage = rawMonochromeSineImage.*gaussianWindow;

% Put it into cal format.  Each pixel in cal format is one column.  Here
% there is just one row since it is a monochrome image at this point.
rawMonochromeUnquantizedContrastGaborCal = ImageToCalFormat(rawMonochromeUnquantizedContrastGaborImage);

%% Quantize the contrast image to a (large) fixed number of levels.
%
% This allows us to speed up the image conversion without any meaningful
% loss of precision. If you don't like it, increase number of quantization
% bits until you are happy again.
nQuantizeBits = 9;
nQuantizeLevels = 2^nQuantizeBits;
rawMonochromeContrastGaborCal = 2*(PrimariesToIntegerPrimaries((rawMonochromeUnquantizedContrastGaborCal+1)/2,nQuantizeLevels)/(nQuantizeLevels-1))-1;

% Plot of how well point cloud method does in obtaining desired contrats.
figure; clf;
plot(rawMonochromeUnquantizedContrastGaborCal(:),rawMonochromeContrastGaborCal(:),'r+');
axis('square');
xlim([0 1]); ylim([0 1]);
xlabel('Unquantized Gabor contrasts');
ylabel('Quantized Gabor contrasts');
title('Effect of contrast quantization');

%% Get cone contrast/excitation gabor image.
%
% Scale target cone contrast vector at max excursion by contrast modulation
% at each pixel.  This is done by a single matrix multiply plus a lead
% factor.  We work cal format here as that makes color transforms
% efficient.
desiredContrastGaborCal = spatialGaborTargetContrast*targetStimulusContrastDir*rawMonochromeContrastGaborCal;

% Convert cone contrast to excitations
desiredExcitationsGaborCal = ContrastToExcitation(desiredContrastGaborCal,screenBgExcitations);

% Get primaries using standard calibration code, and desired spd without
% quantizing.
standardPrimariesGaborCal = SensorToPrimary(screenCalObj,desiredExcitationsGaborCal);
desiredSpdGaborCal = PrimaryToSpd(screenCalObj,standardPrimariesGaborCal);

% Gamma correct and quantize (if gamma method set to 2 above; with gamma
% method set to zero there is no quantization).  Then convert back from
% the gamma corrected settings.
standardSettingsGaborCal = PrimaryToSettings(screenCalObj,standardPrimariesGaborCal);
standardPredictedPrimariesGaborCal = SettingsToPrimary(screenCalObj,standardSettingsGaborCal);
standardPredictedExcitationsGaborCal = PrimaryToSensor(screenCalObj,standardPredictedPrimariesGaborCal);
standardPredictedContrastGaborCal = ExcitationsToContrast(standardPredictedExcitationsGaborCal,screenBgExcitations);

% Plot of how well standard method does in obtaining desired contratsfigure; clf;
figure;
set(gcf,'Position',[100 100 1200 600]);
subplot(1,4,1);
plot(desiredContrastGaborCal(1,:),standardPredictedContrastGaborCal(1,:),'r+');
fprintf('Standard image max L contrast: %0.3f\n',max(abs(standardPredictedContrastGaborCal(1,:))));
axis('square');
xlim([-0.15 0.15]); ylim([-0.15 0.15]);
xlabel('Desired L contrast');
ylabel('Predicted L contrast');
title('Standard image method');

subplot(1,4,2);
plot(desiredContrastGaborCal(2,:),standardPredictedContrastGaborCal(2,:),'g+');
fprintf('Standard image max M contrast: %0.3f\n',max(abs(standardPredictedContrastGaborCal(2,:))));
axis('square');
xlim([-0.15 0.15]); ylim([-0.15 0.15]);
xlabel('Desired M contrast');
ylabel('Predicted M contrast');
title('Standard image method');

subplot(1,4,3);
plot(desiredContrastGaborCal(3,:),standardPredictedContrastGaborCal(3,:),'b+');
fprintf('Standard image max S contrast: %0.3f\n',max(abs(standardPredictedContrastGaborCal(3,:))));
axis('square');
xlim([-0.15 0.15]); ylim([-0.15 0.15]);
xlabel('Desired S contrast');
ylabel('Predicted S contrast');
title('Standard image method');

subplot(1,4,4);
plot(desiredContrastGaborCal(4,:),standardPredictedContrastGaborCal(4,:),'c+');
fprintf('Standard image max Mel contrast: %0.3f\n',max(abs(standardPredictedContrastGaborCal(4,:))));
axis('square');
xlim([-0.15 0.15]); ylim([-0.15 0.15]);
xlabel('Desired MEL contrast');
ylabel('Predicted MEL contrast');
title('Standard image method');

%% Set up table of contrasts for all possible settings
[ptCldSettingsCal, ptCldContrastCal] = SetupContrastPointLookup(screenCalObj,screenBgExcitations,'verbose',VERBOSE);

%% Get image from table, in cal format
uniqueQuantizedSettingsGaborCal = SettingsFromLookup(desiredContrastGaborCal,ptCldContrastCal,ptCldSettingsCal);

% Print out min/max of settings
fprintf('Gabor image min/max settings: %0.3f, %0.3f\n',min(uniqueQuantizedSettingsGaborCal(:)), max(uniqueQuantizedSettingsGaborCal(:)));

% Get contrasts we think we have obtianed
uniqueQuantizedExcitationsGaborCal = SettingsToSensor(screenCalObj,uniqueQuantizedSettingsGaborCal);
uniqueQuantizedContrastGaborCal = ExcitationsToContrast(uniqueQuantizedExcitationsGaborCal,screenBgExcitations);

% Plot of how well point cloud method does in obtaining desired contratsfigure; clf;
figure;
set(gcf,'Position',[100 100 1200 600]);
subplot(1,4,1);
plot(desiredContrastGaborCal(1,:),uniqueQuantizedContrastGaborCal(1,:),'r+');
fprintf('Quantized unique point image max L contrast: %0.3f\n',max(abs(uniqueQuantizedContrastGaborCal(1,:))));
axis('square');
xlim([-0.15 0.15]); ylim([-0.15 0.15]);
xlabel('Desired L contrast');
ylabel('Predicted L contrast');
title('Quantized unique point cloud image method');

subplot(1,4,2);
plot(desiredContrastGaborCal(2,:),uniqueQuantizedContrastGaborCal(2,:),'g+');
fprintf('Quantized unique point image max M contrast: %0.3f\n',max(abs(uniqueQuantizedContrastGaborCal(2,:))));
axis('square');
xlim([-0.15 0.15]); ylim([-0.15 0.15]);
xlabel('Desired M contrast');
ylabel('Predicted M contrast');
title('Quantized unique point cloud image method');

subplot(1,4,3);
plot(desiredContrastGaborCal(3,:),uniqueQuantizedContrastGaborCal(3,:),'b+');
fprintf('Quantized unique point image max S contrast: %0.3f\n',max(abs(uniqueQuantizedContrastGaborCal(3,:))));
axis('square');
xlim([-0.15 0.15]); ylim([-0.15 0.15]);
xlabel('Desired S contrast');
ylabel('Predicted S contrast');
title('Quantized unique point cloud image method');

subplot(1,4,4);
plot(desiredContrastGaborCal(4,:),uniqueQuantizedContrastGaborCal(4,:),'c+');
fprintf('Quantized unique point image max Mel contrast: %0.3f\n',max(abs(uniqueQuantizedContrastGaborCal(4,:))));
axis('square');
xlim([-0.15 0.15]); ylim([-0.15 0.15]);
xlabel('Desired MEL contrast');
ylabel('Predicted MEL contrast');
title('Quantized unique point cloud image method');

%% Convert representations we want to take forward to image format
desiredContrastGaborImage = CalFormatToImage(desiredContrastGaborCal,imageN,imageN);
standardPredictedContrastImage = CalFormatToImage(standardPredictedContrastGaborCal,imageN,imageN);
standardSettingsGaborImage = CalFormatToImage(standardSettingsGaborCal,imageN,imageN);
uniqueQuantizedContrastGaborImage = CalFormatToImage(uniqueQuantizedContrastGaborCal,imageN,imageN);

%% SRGB image via XYZ, scaled to display
predictedXYZCal = T_xyz*desiredSpdGaborCal;
SRGBPrimaryCal = XYZToSRGBPrimary(predictedXYZCal);
scaleFactor = max(SRGBPrimaryCal(:));
SRGBCal = SRGBGammaCorrect(SRGBPrimaryCal/(2*scaleFactor),0);
SRGBImage = uint8(CalFormatToImage(SRGBCal,imageN,imageN));

% Show the SRGB image
figure; imshow(SRGBImage);
title('SRGB Gabor Image');

%% Show the settings image
figure; clf;
imshow(standardSettingsGaborImage);
title('Image of settings');

%% Plot slice through predicted LMS contrast image.
%
% Note that the y-axis in this plot is individual cone contrast, which is
% not the same as the vector length contrast of the modulation.
figure; hold on
plot(1:imageN,100*standardPredictedContrastImage(centerN,:,1),'r+','MarkerFaceColor','r','MarkerSize',4);
plot(1:imageN,100*desiredContrastGaborImage(centerN,:,1),'r','LineWidth',0.5);

plot(1:imageN,100*standardPredictedContrastImage(centerN,:,2),'g+','MarkerFaceColor','g','MarkerSize',4);
plot(1:imageN,100*desiredContrastGaborImage(centerN,:,2),'g','LineWidth',0.5);

plot(1:imageN,100*standardPredictedContrastImage(centerN,:,3),'b+','MarkerFaceColor','b','MarkerSize',4);
plot(1:imageN,100*desiredContrastGaborImage(centerN,:,3),'b','LineWidth',0.5);

plot(1:imageN,100*standardPredictedContrastImage(centerN,:,4),'c+','MarkerFaceColor','b','MarkerSize',4);
plot(1:imageN,100*desiredContrastGaborImage(centerN,:,4),'c','LineWidth',0.5);
if (screenGammaMethod == 2)
    title('Image Slice, SensorToSettings Method, Quantized Gamma, LMS Cone Contrast');
else
    title('Image Slice, SensorToSettings Method, No Quantization, LMS Cone Contrast');
end
xlabel('x position (pixels)')
ylabel('LMS Cone Contrast (%)');
ylim([-plotAxisLimit plotAxisLimit]);

%% Plot slice through point cloud LMS contrast image.
%
% Note that the y-axis in this plot is individual cone contrast, which is
% not the same as the vector length contrast of the modulation.
figure; hold on
plot(1:imageN,100*uniqueQuantizedContrastGaborImage(centerN,:,1),'r+','MarkerFaceColor','r','MarkerSize',4);
plot(1:imageN,100*desiredContrastGaborImage(centerN,:,1),'r','LineWidth',0.5);

plot(1:imageN,100*uniqueQuantizedContrastGaborImage(centerN,:,2),'g+','MarkerFaceColor','g','MarkerSize',4);
plot(1:imageN,100*desiredContrastGaborImage(centerN,:,2),'g','LineWidth',0.5);

plot(1:imageN,100*uniqueQuantizedContrastGaborImage(centerN,:,3),'b+','MarkerFaceColor','b','MarkerSize',4);
plot(1:imageN,100*desiredContrastGaborImage(centerN,:,3),'b','LineWidth',0.5);

plot(1:imageN,100*uniqueQuantizedContrastGaborImage(centerN,:,4),'c+','MarkerFaceColor','b','MarkerSize',4);
plot(1:imageN,100*desiredContrastGaborImage(centerN,:,4),'c','LineWidth',0.5);
title('Image Slice, Point Cloud Method, LMS Cone Contrast');
xlabel('x position (pixels)')
ylabel('LMS Cone Contrast (%)');
ylim([-plotAxisLimit plotAxisLimit]);

%% Generate some settings values corresponding to known contrasts
%
% The reason for this is to measure and check these.  This logic follows
% how we handled an actual gabor image above. We don't actually need to
% quantize to 14 bits here on the contrast, but nor does it hurt.
rawMonochromeUnquantizedContrastCheckCal = [0 0.05 -0.05 0.10 -0.10 0.15 -0.15 0.20 -0.20 0.25 -0.25 0.5 -0.5 1 -1];
rawMonochromeContrastCheckCal = 2*(PrimariesToIntegerPrimaries((rawMonochromeUnquantizedContrastCheckCal+1)/2,nQuantizeLevels)/(nQuantizeLevels-1))-1;
desiredContrastCheckCal = spatialGaborTargetContrast*targetStimulusContrastDir*rawMonochromeContrastCheckCal;
desiredExcitationsCheckCal = ContrastToExcitation(desiredContrastCheckCal,screenBgExcitations);

% For each check calibration find the settings that
% come as close as possible to producing the desired excitations.
%
% If we measure for a uniform field the spectra corresopnding to each of
% the settings in the columns of ptCldScreenSettingsCheckCall, then
% compute the cone contrasts with respect to the backgound (0 contrast
% measurement, first settings), we should approximate the cone contrasts in
% desiredContrastCheckCal. 
ptCldScreenSettingsCheckCal = SettingsFromLookup(desiredContrastCheckCal,ptCldContrastCal,ptCldSettingsCal);
ptCldScreenPrimariesCheckCal = SettingsToPrimary(screenCalObj,ptCldScreenSettingsCheckCal);
ptCldScreenSpdCheckCal = PrimaryToSpd(screenCalObj,ptCldScreenPrimariesCheckCal);
ptCldScreenExcitationsCheckCal = SettingsToSensor(screenCalObj,ptCldScreenSettingsCheckCal);
ptCldScreenContrastCheckCal = ExcitationsToContrast(ptCldScreenExcitationsCheckCal,screenBgExcitations);
figure; clf; hold on;
plot(desiredContrastCheckCal(4,:),ptCldScreenContrastCheckCal(4,:),'co','MarkerSize',10,'MarkerFaceColor','c');
plot(desiredContrastCheckCal(3,:),ptCldScreenContrastCheckCal(3,:),'bo','MarkerSize',10,'MarkerFaceColor','b');
plot(desiredContrastCheckCal(2,:),ptCldScreenContrastCheckCal(2,:),'go','MarkerSize',10,'MarkerFaceColor','g');
plot(desiredContrastCheckCal(1,:),ptCldScreenContrastCheckCal(1,:),'ro','MarkerSize',10,'MarkerFaceColor','r');
xlim([0 plotAxisLimit/100]); ylim([0 plotAxisLimit/100]); axis('square');
xlabel('Desired'); ylabel('Obtained');
title('Desired versus obtained check contrasts');

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
    screenPrimarySpdCheck(:,pp) = PrimaryToSpd(channelCalObjs{pp},SettingsToPrimary(channelCalObjs{pp},screenPrimarySettings(:,pp)));
end
figure; clf; hold on
plot(SToWls(S),screenPrimarySpdCheck,'k','LineWidth',4);
plot(SToWls(S),screenPrimarySpd,'r','LineWidth',2);
xlabel('Wavelength'); ylabel('Radiance');
title('Check of consistency between screen primaries and screen primary spds');

%% Save out what we need to check things on the DLP
screenSettingsImage = standardSettingsGaborImage;
if (ispref('SpatioSpectralStimulator','SACCMelanopsin'))
    dayTimestr = datestr(now,'yyyy-mm-dd_HH-MM-SS');
    testFiledir = getpref('SpatioSpectralStimulator','SACCMelanopsin');
    testFilename = fullfile(testFiledir,'testImageData');
    save(testFilename,'S','T_cones','T_receptors','screenCalObj','channelCalObjs','screenSettingsImage', ...
        'screenPrimaryPrimaries','screenPrimarySettings','screenPrimarySpd',...
        'desiredContrastCheckCal','rawMonochromeUnquantizedContrastCheckCal', ...
        'ptCldScreenSettingsCheckCal','ptCldScreenContrastCheckCal','ptCldScreenSpdCheckCal', ...
        'nQuantizeLevels','screenNInputLevels','targetStimulusContrastDir','spatialGaborTargetContrast',...
        'targetScreenPrimaryContrast','targetLambda');
end
