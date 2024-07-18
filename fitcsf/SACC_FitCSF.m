%% SACC_FitCSF
%
% This is to fit CSF curve for SACC project.
%
% See also:
%    asymmetricParabolicFunc, SACC_FitCSF_OLD

% History:
%    01/13/23   smo    - Started on it.
%    01/19/23   smo    - First fitting CSF with the function and it seems
%                        pretty good. Will be elaborated.
%    02/03/23   smo    - Added a feature to use bootstrapped values to find
%                        a smoothing parameter for smooth spline curve.
%    02/08/23   smo    - Now we can cross-validate with two separate
%                        bootstrapped data when we fit CSF with smooth
%                        spline function.
%    02/13/23   smo    - Now we fit and plot the data with all methods at
%                        the same time.
%    02/15/23   smo    - Added an option to save the CSF plot.
%    02/21/23   smo    - Added an option to calculate and bootstrap AUC.
%                        Also, we can choose which domain to fit CSF either
%                        linear or log.
%    03/08/23   smo    - Cleared up the options that we will not use
%                        anymore. The one with all the options has been
%                        saved as a separate file named SACC_FitCSF_OLD.m.
%    03/14/23   smo    - Added an option to choose subject and filter to
%                        fit.
%    03/16/23   smo    - Added an option to fit CSF with desired smoothing
%                        parameter. It can be a single value or as many as
%                        we want.
%    03/20/23   smo    - Added an option to use fmincon to search smoothing
%                        parameter when using Smooth spline function.
%    03/29/23   smo    - Added an option to lock randomization per each
%                        filter/subject combination.
%    04/17/23   smo    - Fitting has been updated to be done in log CS and
%                        linear SF space.
%    10/12/23   smo    - Added an option to save the figure in the
%                        different directory if we omit the bad contrasts.

%% Initialize.
clear; close all;

%% Set options to fit and plot CSF.
%
% Plotting options.
OneFigurePerSub = false;
WaitForKeyToPlot = false;
PlotAUC = true;
SaveCSFPlot = true;

% Figure size and position.
figureSize = 800;
figurePositionData = [200 300 figureSize figureSize-200];
figurePositionCross = [200+figureSize 300 figureSize figureSize];

% Fitting options.
BootstrapCSF = true;

% Set this to true if we fitted the PF without the bad points (as of
% 10/12/23).
FITPFONLYGOODTESTCONTRASTS = true;

% Set directory to differently.
if (FITPFONLYGOODTESTCONTRASTS)
    whichPref = 'SCMDAnalysis';
else
    whichPref = 'SACCAnalysis';
end

% Set the sensitivity range to pick for bootstrapped values.
minThresholdContrastBoot = 0.0003;
maxThresholdContrastBoot = 0.1;
minSensitivityBoot = log10(1/maxThresholdContrastBoot);
maxSensitivityBoot = log10(1/minThresholdContrastBoot);

% OptionSearchSmoothParam can be one of the followings {'crossValBootAcross',
% 'crossValBootAcrossFmincon', 'type'}.
OptionSearchSmoothParam = 'crossValBootAcrossFmincon';

if strcmp(OptionSearchSmoothParam,'type')
    minSmoothingParamType = 0.99;
    maxSmoothingParamType = 1;
    intervalSmoothingParamType = 0.00005;
    smoothingParamsType = [minSmoothingParamType : intervalSmoothingParamType : maxSmoothingParamType];
    nSmoothingParamsType = length(smoothingParamsType);
else
    nSmoothingParamsType = 1;
end

% Pick subject and filter to fit.
pickSubjectAndFilter = false;
whichSubject = '002';
whichFilter = 'B';

% Save text summary file.
RECORDTEXTSUMMARYPERSUB = true;

% Fix the randomization if you want.
lockRand = true;

%% Load and read out the data.
if ispref('SpatioSpectralStimulator',whichPref)
    testFiledir = getpref('SpatioSpectralStimulator',whichPref);
end
testFilename = fullfile(testFiledir,'CSFAnalysisOutput');
theData = load(testFilename);

% Close the plots if any pops up.
close all;

% Subject info.
subjectNameOptions = theData.subjectNameOptions;

% Filter options.
filterOptions = theData.filterOptions;

% Get threshold data. Each variable is aligned in [subject, SF, filter].
thresholdFittedRaw = theData.thresholdFittedRaw;
thresholdFittedBootRaw = theData.thresholdFittedBootRaw;
medianThresholdBootRaw = theData.medianThresholdBootRaw;
lowThresholdBootRaw = theData.lowThresholdBootRaw;
highThresholdBootRaw = theData.highThresholdBootRaw;
thresholdFittedBootCross1Raw = theData.thresholdFittedBootCross1Raw;
thresholdFittedBootCross2Raw = theData.thresholdFittedBootCross2Raw;

%% Fitting CSF starts here.
%
% Get the number of available subjects and filters.
nSubjects = length(subjectNameOptions);
nFilters = length(filterOptions);

% Set up big lists of what was run.  Want these at full dimension.
subjectBigList = cell(nSubjects,nFilters);
AUCBigList = cell(nSubjects,nFilters);
medianBootAUCBigList = cell(nSubjects,nFilters);
lowBootCIAUCBigList = cell(nSubjects,nFilters);
highBootCIAUCBigList = cell(nSubjects,nFilters);
smoothingParamBigList = cell(nSubjects,nFilters);
myCSValsBigList = cell(nSubjects,nFilters);

% Fitting happens here one by one per subject.
for ss = 1:nSubjects
    % Set a target subject.
    subjectName = subjectNameOptions{ss};
    
    % If we run one specific subject, we will pass the other subjects.
    if (pickSubjectAndFilter)
        if ~strcmp(subjectName,whichSubject)
            continue;
        end
    end
    
    % Set available spatial frequency data for the subject.
    sineFreqCyclesPerDeg = theData.spatialFrequencyOptions(:,ss);
    
    % Here we remove empty cells. It shows a cell empty when a subject does
    % not have all possible spatial frequency data.
    sineFreqCyclesPerDeg = sineFreqCyclesPerDeg(...
        find(~cellfun(@isempty,sineFreqCyclesPerDeg)));
    
    % The number of available data for the subject. It should be 5 to
    % proceed the fitting.
    nSineFreqCyclesPerDeg = length(sineFreqCyclesPerDeg);
    
    % Run fitting only if there are all spatial frequency data.
    if (nSineFreqCyclesPerDeg == 5)
        % Get spatial frequency data in double.
        for dd = 1:nSineFreqCyclesPerDeg
            sineFreqCyclesPerDegNum(dd) = sscanf(sineFreqCyclesPerDeg{dd},'%d');
        end
        
        %% Make a new plot per each subject if you want.
        if (OneFigurePerSub)
            % Data figure info.
            dataFig = figure; clf; hold on;
            set(gcf,'position',figurePositionData);
            
            if strcmp(OptionSearchSmoothParam,'CrossValBootAcross')
                % Cross-validation figure info.
                crossFig = figure; hold on;
                set(gcf,'position',figurePositionCross);
            end
        end
        
        % Here we read out five values of the thresholds (so, five spatial
        % frequency) to fit CSF curve.
        for ff = 1:nFilters
            % Lock randomization order if you want. We will assign an
            % unique seed number to each filter/subject combination.
            if (lockRand)
                numSubject = str2double(subjectName);
                rngSeed = ff+(numSubject-1)*nFilters;
                rng(rngSeed);
            end
            
            % Make a new plot per each filter of the subject.
            if (~OneFigurePerSub)
                % Data figure info.
                dataFig = figure; clf; hold on;
                set(gcf,'position',figurePositionData);
                
                if strcmp(OptionSearchSmoothParam,'CrossValBootAcross')
                    % Cross-validation figure info.
                    crossFig = figure; hold on;
                    set(gcf,'position',figurePositionCross);
                end
            end
            
            % Here we can choose filters to run as desired. Allocate number
            % to each filter as [A=1, B=2, C=3, D=4, E=5].
            if (pickSubjectAndFilter)
                switch whichFilter
                    case 'A'
                        numWhichFilter = 1;
                    case 'B'
                        numWhichFilter = 2;
                    case 'C'
                        numWhichFilter = 3;
                    case 'D'
                        numWhichFilter = 4;
                    case 'E'
                        numWhichFilter = 5;
                end
                
                % Skip happens here.
                if ~(ff == numWhichFilter)
                    continue;
                end
            end
            
            % Read out the variables per each filter. These values are
            % linear units, which we will be converted on log space.
            thresholds = thresholdFittedRaw(ss,:,ff);
            thresholdsBoot = squeeze(thresholdFittedBootRaw(ss,:,ff,:));
            medianThresholdsBoot = medianThresholdBootRaw(ss,:,ff);
            lowThresholdBoot = lowThresholdBootRaw(ss,:,ff);
            highThresholdBoot = highThresholdBootRaw(ss,:,ff);
            thresholdsBootCross1 = squeeze(thresholdFittedBootCross1Raw(ss,:,ff,:));
            thresholdsBootCross2 = squeeze(thresholdFittedBootCross2Raw(ss,:,ff,:));
            
            % Some checks that bookkeeping is working. Note that
            % 'thresholdBootLow' and 'thresholdBootHigh' are the ends
            % of confidence interval (80%), not the entire range.
            bootConfInterval = 0.8;
            thresholdBootLowCheck = prctile(thresholdsBoot',100*(1-bootConfInterval)/2);
            thresholdBootHighCheck = prctile(thresholdsBoot',100-100*(1-bootConfInterval)/2);
            
            % Check low boot strap range, so 10% of the entire range.
            numDigitsRound = 4;
            if (any(round(thresholdBootLowCheck,numDigitsRound) ~= round(lowThresholdBoot,numDigitsRound)))
                error('Inconsistency in low bootstrapped threshold');
            end
            
            % Check high bootstrap range, so 90% of the entire range.
            if (any(round(thresholdBootHighCheck,numDigitsRound) ~= round(highThresholdBoot,numDigitsRound)))
                error('Inconsistency in high bootstrapped threshold');
            end
            
            % Clear the variables for checking the values.
            clear thresholdBootLowCheck thresholdBootHighCheck;
            
            % Remove odd bootstrapping results. There are some negative
            % threshold bootstrapping fitting results on linear space. It
            % does not make sense, so we convert the number into 'nan' so
            % that it won't affect our sampling procedure.
            thresholdsBoot(thresholdsBoot<0) = nan;
            thresholdsBootCross1(thresholdsBootCross1<0) = nan;
            thresholdsBootCross2(thresholdsBootCross2<0) = nan;
            
            %% Calculate log sensitivity.
            %
            % PF fitted thresholds.
            sensitivity = log10(1./thresholds);
            sensitivityMedianBoot = log10(1./medianThresholdsBoot);
            
            % Bootstrapped values.
            %
            % For calculation of confindence
            % interval from bootstrap, (low) threshold becomes (high)
            % sensitivity, and vice versa.
            sensitivityBoot = log10(1./thresholdsBoot);
            sensitivityBootHigh = log10(1./lowThresholdBoot);
            sensitivityBootLow = log10(1./highThresholdBoot);
            
            % Additional bootstrapped values for cross-validation.
            sensitivityBootCross1 = log10(1./thresholdsBootCross1);
            sensitivityBootCross2 = log10(1./thresholdsBootCross2);
            
            % Calculate spatial frequency in log space.
            sineFreqCyclesPerDegLog = log10(sineFreqCyclesPerDegNum);
            
            %% Sort each array in an ascending order of spatial frequency.
            [sineFreqCyclesPerDegNumSorted I] = sort(sineFreqCyclesPerDegNum,'ascend');
            
            % Sorted according to the order of spatial frequency.
            sensitivitySorted = sensitivity(I);
            sensitivityMedianBootSorted = sensitivityMedianBoot(I);
            sensitivityBootHighSorted = sensitivityBootHigh(I);
            sensitivityBootLowSorted = sensitivityBootLow(I);
            sensitivityBootSorted = sensitivityBoot(I,:);
            sensitivityBootCross1Sorted = sensitivityBootCross1(I,:);
            sensitivityBootCross2Sorted = sensitivityBootCross2(I,:);
            
            % Set variables to fit CSF.
            mySFVals = sineFreqCyclesPerDegNumSorted;
            myCSVals = sensitivitySorted;
            
            % Set all bootstrapped values.
            myCSValsBoot = sensitivityBootSorted';
            myCSValsCross1 = sensitivityBootCross1Sorted';
            myCSValsCross2 = sensitivityBootCross2Sorted';
            nBootPoints = size(myCSValsBoot,1);
            
            %% Set searching options for smoothing parameter.
            %
            % Set the number of points for plotting the results.
            nSmoothPoints = 100;
            
            % Set the smoothing param searching options.
            nSmoothingParams = 30;
            minSmoothingParam = 0;
            maxSmoothingParam = 1;
            crossSmoothingParams = linspace(minSmoothingParam,maxSmoothingParam,nSmoothingParams);
            
            %% Find optimal smoothing parameter for CSF.
            %
            % Here we can use bootstrap method or just type a number.
            switch OptionSearchSmoothParam
                case 'crossValBootAcross'
                    % Make a loop for testing smoothing paramemters.
                    for sss = 1:length(crossSmoothingParams)
                        smoothCrossError(sss) = 0;
                        
                        % Bootstrap for cross-validation happens here.
                        nCrossValBootAcross = 20;
                        for cc = 1:nCrossValBootAcross
                            
                            % Draw new fit/cross dataset (N=20)
                            % out of bootstrapped values
                            % (N=100). Once we drew the set, we
                            % will use the same set for all
                            % smoothing params.
                            if (sss == 1)
                                for zz = 1:length(mySFVals)
                                    crossIndex = randi(nBootPoints,1,1);
                                    bootCSFDataFit{cc}(zz) = myCSValsCross1(crossIndex,zz);
                                    bootCSFDataCross{cc}(zz) = myCSValsCross2(crossIndex,zz);
                                end
                            end
                            
                            % Fit curve with the training set.
                            smoothFitCross = fit(mySFVals',bootCSFDataFit{cc}','smoothingspline','SmoothingParam',crossSmoothingParams(sss));
                            
                            % Get the predicted result of testing value.
                            smoothDataPredsCross = feval(smoothFitCross,mySFVals');
                            
                            % Calculate the error.
                            smoothCrossError(sss) = smoothCrossError(sss) + sum((bootCSFDataCross{cc}' - smoothDataPredsCross).^2);
                        end
                        
                        % Print out the progress.
                        if (sss == round(length(crossSmoothingParams)*0.25))
                            fprintf('Method = (%s) / Smoothing param testing progress - (%s) \n', OptionSearchSmoothParam, '25%');
                        elseif (sss == round(length(crossSmoothingParams)*0.50))
                            fprintf('Method = (%s) / Smoothing param testing progress - (%s) \n', OptionSearchSmoothParam,  '50%');
                        elseif (sss == round(length(crossSmoothingParams)*0.75))
                            fprintf('Method = (%s) / Smoothing param testing progress - (%s) \n', OptionSearchSmoothParam,  '75%');
                        elseif (sss == length(crossSmoothingParams))
                            fprintf('Method = (%s) / Smoothing param testing progress - (%s) \n', OptionSearchSmoothParam,  '100%');
                        end
                    end
                    
                    % Set the smoothing params that has the smallest error.
                    [~,index] = min(smoothCrossError);
                    smoothingParam = crossSmoothingParams(index);
                    
                case 'crossValBootAcrossFmincon'
                    % Draw new fit/cross dataset (N=20)
                    % out of bootstrapped values
                    % (N=100). Once we drew the set, we
                    % will use the same set for all
                    % smoothing params.
                    nCrossValBootAcross = 20;
                    for cc = 1:nCrossValBootAcross
                        for zz = 1:length(mySFVals)
                            % Here make a while loop until it draws
                            % reasonable values.
                            while 1
                                crossIndex = randi(nBootPoints,1,1);
                                bootCSFDataFitTemp = myCSValsCross1(crossIndex,zz);
                                bootCSFDataCrossTemp = myCSValsCross2(crossIndex,zz);
                                if (~isnan(bootCSFDataFitTemp) && ~isnan(bootCSFDataCrossTemp))
                                    if (bootCSFDataFitTemp >= minSensitivityBoot & bootCSFDataFitTemp <= maxSensitivityBoot)
                                        if (bootCSFDataCrossTemp >= minSensitivityBoot & bootCSFDataCrossTemp <= maxSensitivityBoot)
                                            break;
                                        end
                                    end
                                end
                            end
                            
                            % Save the values.
                            bootCSFDataFit{cc}(zz) = bootCSFDataFitTemp;
                            bootCSFDataCross{cc}(zz) = bootCSFDataCrossTemp;
                        end
                    end
                    
                    % Set bounds for parameter x to 0 and 1.
                    x0 = 0.5;
                    vlb = 0;
                    vub = 1;
                    A = [];
                    b = [];
                    Aeq = [];
                    beq = [];
                    options = optimset('fmincon');
                    
                    % Show message before running fmincon.
                    fprintf('Method = (%s) / Starting... \n',OptionSearchSmoothParam);
                    
                    % Run fmincon to find best cross validation smoothing
                    % parameter.
                    x_found = fmincon(@(x) SmoothnessSearchErrorFunction(x, mySFVals, bootCSFDataFit, bootCSFDataCross), ...
                        x0, A, b, Aeq, beq, vlb, vub, [], options);
                    smoothingParam = x_found(1);
                    
                    % Show message again after completing fmincon.
                    fprintf('Method = (%s) / Completed! \n',OptionSearchSmoothParam);
                    
                case 'type'
                    % Type a number manually.
                    smoothingParam = smoothingParamsType;
            end
            
            %% Fit CCSF and Calculate AUC.
            %
            % We make this part in a loop so that we can fit multiple
            % smoothing parameters at once.
            nSmoothingParams = length(smoothingParam);
            for mm = 1:nSmoothingParams
                % Check if smoothing parameter is in the range.
                if (smoothingParam(mm) > 1)
                    smoothingParam(mm) = 1;
                elseif (smoothingParam(mm) < 0)
                    smoothingParam(mm) = 0;
                end
                
                % Fit the data with the optimal smoothing parameter.
                smoothFit = fit(mySFVals',myCSVals','smoothingspline','SmoothingParam',smoothingParam(mm));
                
                % Make smooth plot.
                smoothPlotSFVals = log10(logspace(min(mySFVals),max(mySFVals),nSmoothPoints))';
                smoothPlotPreds(:,mm) = feval(smoothFit,smoothPlotSFVals);
                
                % Show progress.
                fprintf('Smoothing param fitting progress - (%d/%d) \n', mm, nSmoothingParams);
            end
            
            % Get the area under the curve (AUC).
            nPointsCalAUC = 1000;
            calAUCSFVals = log10(logspace(min(mySFVals),max(mySFVals),nPointsCalAUC))';
            calAUCPreds = feval(smoothFit,calAUCSFVals);
            
            % Save the values for plotting. These two variables will be
            % updated below.
            calAUCSFValsPlot = calAUCSFVals;
            calAUCPredsPlot = calAUCPreds;
            
            % Calculate AUC.
            AUC = trapz(calAUCSFVals,calAUCPreds);
            
            % Make smooth plot.
            smoothPlotSFValsBoot = log10(logspace(min(mySFVals),max(mySFVals),nSmoothPoints))';
            smoothPlotPredsBoot = feval(smoothFit,smoothPlotSFValsBoot);
            
            % Show progress.
            fprintf('\t CSF fitting and AUC calculation completed! \n\n');
            
            %% Bootstrapping to fit CCSF.
            if strcmp(OptionSearchSmoothParam,'crossValBootAcrossFmincon')
                if (BootstrapCSF)
                    nBootCSF = 20;
                    for nn = 1:nBootCSF
                        % Generate new CS values set to fit the curve.
                        for zz = 1:length(mySFVals)
                            % Make a loop to pick a value within the set
                            % range of sensitivity. This prevents to pick
                            % not sensible results from the bootstrapped
                            % values.
                            while 1
                                randIndex = randi(nBootPoints,1,1);
                                myCSValsBootFminconTemp = myCSValsBoot(randIndex,zz);
                                if ~isnan(myCSValsBootFminconTemp)
                                    if (myCSValsBootFminconTemp >= minSensitivityBoot & myCSValsBootFminconTemp <= maxSensitivityBoot)
                                        if (myCSValsBootFminconTemp >= minSensitivityBoot & myCSValsBootFminconTemp <= maxSensitivityBoot)
                                            break;
                                        end
                                    end
                                end
                            end
                            myCSValsBootFmincon(zz) = myCSValsBootFminconTemp;
                        end
                        
                        % Draw new fit/cross dataset (N=20)
                        % out of bootstrapped values
                        % (N=100). Once we drew the set, we
                        % will use the same set for all
                        % smoothing params.
                        nCrossValBootAcross = 20;
                        for cc = 1:nCrossValBootAcross
                            for zz = 1:length(mySFVals)
                                % Here make a while loop until it draws
                                % reasonable values.
                                while 1
                                    crossIndex = randi(nBootPoints,1,1);
                                    bootCSFDataFitTemp = myCSValsCross1(crossIndex,zz);
                                    bootCSFDataCrossTemp = myCSValsCross2(crossIndex,zz);
                                    if (bootCSFDataFitTemp >= minSensitivityBoot & bootCSFDataFitTemp <= maxSensitivityBoot)
                                        if (bootCSFDataCrossTemp >= minSensitivityBoot & bootCSFDataCrossTemp <= maxSensitivityBoot)
                                            break;
                                        end
                                    end
                                end
                                
                                % Save the results.
                                bootCSFDataFit{cc}(zz) = bootCSFDataFitTemp;
                                bootCSFDataCross{cc}(zz) = bootCSFDataCrossTemp;
                            end
                        end
                        
                        % Set bounds for parameter x to 0 and 1.
                        x0 = 0.5;
                        vlb = 0;
                        vub = 1;
                        A = [];
                        b = [];
                        Aeq = [];
                        beq = [];
                        options = optimset('fmincon');
                        
                        % Run fmincon to find best cross validation smoothing
                        % parameter.
                        x_found = fmincon(@(x) SmoothnessSearchErrorFunction(x, mySFVals, bootCSFDataFit, bootCSFDataCross), ...
                            x0, A, b, Aeq, beq, vlb, vub, [], options);
                        smoothingParamBootFmincon(nn) = x_found(1);
                        
                        % Make sure smoothing param is in the range.
                        if (smoothingParamBootFmincon(nn) > 1)
                            smoothingParamBootFmincon(nn) = 1;
                        elseif (smoothingParamBootFmincon(nn) < 0)
                            smoothingParamBootFmincon(nn) = 0;
                        end
                        
                        % Show message again after completing fmincon.
                        fprintf('Method = (%s) / Bootstrapping in progress (%d/%d) \n',OptionSearchSmoothParam,nn,nBootCSF);
                        
                        % Fit happens here.
                        smoothFit = fit(mySFVals',myCSValsBootFmincon','smoothingspline','SmoothingParam',smoothingParamBootFmincon(nn));
                        
                        % Get the predicted values to plot.
                        smoothPlotPredsBoot(:,nn) = feval(smoothFit,smoothPlotSFVals);
                        
                        % Calculate AUC.
                        calAUCPreds = feval(smoothFit,calAUCSFVals);
                        AUCBoot(nn) = trapz(calAUCSFVals,calAUCPreds);
                    end
                else
                    nBootCSF = 0;
                end
            end
            
            %% Bootstrapping AUC (NOT RUNNUNG THIS PART).
            %
            % This part is basically the same as the above (bootstrapping
            % CCSF and calculate AUC of each), but doing it by grid-search,
            % not using fmincon. This is an old way to run bootstrapping
            % before we started using fmincon. We keep the format here, but
            % we will not run this part for our final analysis (as of
            % 10/17/23).
            %
            % Thus, we will keep 'BootstrapAUC' to false so that it won't
            % run in this routine.
            BootstrapAUC = false;
            
            % Set the number of bootrapping the AUC.
            nBootAUC = 20;
            if (BootstrapAUC)
                fprintf('\t Bootstrapping AUC is going to be started! \n');
                
                for aaa = 1:nBootAUC
                    % Make a loop for testing smoothing paramemters.
                    for sss = 1:length(crossSmoothingParams)
                        smoothCrossErrorBootAUC(sss,aaa) = 0;
                        
                        % Bootstrap for cross-validation happens here.
                        nCrossValBootAcross = 20;
                        for cc = 1:nCrossValBootAcross
                            
                            % Draw new fit/cross dataset (N=20)
                            % out of bootstrapped values
                            % (N=100). Once we drew the set, we
                            % will use the same set for all
                            % smoothing params.
                            if (sss == 1)
                                for zz = 1:length(mySFVals)
                                    crossIndex = randi(nBootPoints,1,1);
                                    bootCSFDataFit{cc}(zz) = myCSValsCross1(crossIndex,zz);
                                    bootCSFDataCross{cc}(zz) = myCSValsCross2(crossIndex,zz);
                                end
                            end
                            
                            % Fit curve with the training set.
                            smoothFitCross = fit(mySFVals',bootCSFDataFit{cc}','smoothingspline','SmoothingParam',crossSmoothingParams(sss));
                            
                            % Get the predicted result of testing value.
                            smoothDataPredsCross = feval(smoothFitCross,mySFVals');
                            
                            % Calculate the error.
                            smoothCrossErrorBootAUC(sss,aaa) = smoothCrossErrorBootAUC(sss,aaa) + sum((bootCSFDataCross{cc}' - smoothDataPredsCross).^2);
                        end
                        
                        % Print out the progress.
                        if (sss == round(length(crossSmoothingParams)*0.25))
                            fprintf('Method = (%s) / Smoothing param testing progress - (%s) \n', OptionSearchSmoothParam, '25%');
                        elseif (sss == round(length(crossSmoothingParams)*0.50))
                            fprintf('Method = (%s) / Smoothing param testing progress - (%s) \n', OptionSearchSmoothParam,  '50%');
                        elseif (sss == round(length(crossSmoothingParams)*0.75))
                            fprintf('Method = (%s) / Smoothing param testing progress - (%s) \n', OptionSearchSmoothParam,  '75%');
                        elseif (sss == length(crossSmoothingParams))
                            fprintf('Method = (%s) / Smoothing param testing progress - (%s) \n', OptionSearchSmoothParam,  '100%');
                        end
                    end
                    
                    % Print out the progress of bootstrapping
                    % AUC. It will take a while.
                    fprintf('\t Bootstrapping AUC progress - (%d/%d) \n', aaa, nBootAUC);
                    
                    % Set the smoothing params that has the smallest error.
                    [~,indexBootAUC] = min(smoothCrossErrorBootAUC(:,aaa));
                    smoothingParamBootAUC = crossSmoothingParams(indexBootAUC);
                    
                    % Generate new CS values set to fit the curve.
                    for zz = 1:length(mySFVals)
                        myCSValsBootAUC(zz) = myCSValsBoot(randi(nBootPoints,1,1),zz);
                    end
                    
                    % Check if smoothing param is within the range.
                    if (smoothingParamBootAUC > 1)
                        smoothingParamBootAUC = 1;
                    elseif (smoothingParamBootAUC < 0)
                        smoothingParamBootAUC = 0;
                    end
                    
                    % Fit happens here.
                    smoothFit = fit(mySFVals',myCSValsBootAUC','smoothingspline','SmoothingParam',smoothingParamBootAUC);
                    
                    % Get the area under the curve (AUC).
                    nPointsCalAUC = 1000;
                    calAUCSFVals = log10(logspace(min(mySFVals),max(mySFVals),nPointsCalAUC))';
                    calAUCPreds = feval(smoothFit,calAUCSFVals);
                    
                    % Calculate AUC.
                    AUCBoot(aaa) = trapz(calAUCSFVals,calAUCPreds);
                    
                    % Print out the AUC calculation results.
                    fprintf('Calculated AUC (%d/%d) is (%.5f) \n',...
                        aaa, nBootAUC, AUCBoot(aaa));
                end
            else
                fprintf('\t Skipping Bootstrapping AUC! \n');
                if ~(BootstrapCSF)
                    AUCBoot = zeros(1,nBootAUC);
                end
            end
            
            %% Plot cross-validation smoothing param figure.
            if strcmp(OptionSearchSmoothParam,'CrossValBootAcross')
                figure(crossFig); hold on;
                plot(crossSmoothingParams, smoothCrossError,'ko','MarkerSize',6);
                plot(smoothingParam, smoothCrossError(index),'co','MarkerSize',8,'Markerfacecolor','r','Markeredgecolor','k');
                xlabel('Smoothing parameter','fontsize',15);
                ylabel('Cross-validation errors','fontsize',15);
                title('Cross-validation error accoring to smoothing parameter','fontsize',15);
                xlim([minSmoothingParam maxSmoothingParam]);
                legend('All params', 'Optimal param', 'fontsize', 13);
            end
            
            %% Plot data figure from here.
            figure(dataFig);
            
            % Set marker/line options for the plot.
            colorOptionsRaw = {'k.','r.','g.','b.','c.'};
            colorOptionsBoot = {'k+','r+','g+','b+','c+'};
            colorOptionsCSF = {'k-','r-','g-','b-','c-'};
            colorOptionsCI = {'k','r','g','b','c'};
            
            % Set marker color same if we plot it by filter.
            if (~OneFigurePerSub)
                colorOptionsRaw(:) = {'ro'};
                colorOptionsBoot(:) = {'go'};
                colorOptionsCI(:) = {[0.1 0.7 0.1]};
            end
            
            % Set the marker size.
            markerSizePF = 11;
            markerSizeBootMedian = 7;
            
            % Plot raw data.
            plot(sineFreqCyclesPerDegNumSorted, sensitivitySorted, ...
                colorOptionsRaw{ff},'markerfacecolor','r','markersize',markerSizePF,'Markeredgecolor','k');
            plot(sineFreqCyclesPerDegNumSorted, sensitivityMedianBootSorted, ...
                colorOptionsBoot{ff},'markerfacecolor',[0.1 0.7 0.1],'markersize',markerSizeBootMedian,'Markeredgecolor','k');
            
            % Plot confidence Interval.
            errorNeg = abs(sensitivityMedianBootSorted - sensitivityBootLowSorted);
            errorPos = abs(sensitivityBootHighSorted - sensitivityMedianBootSorted);
            e = errorbar(sineFreqCyclesPerDegNumSorted, sensitivityMedianBootSorted, ...
                errorNeg, errorPos, 'color', colorOptionsCI{ff});
            e.LineStyle = 'none';
            
            % Plot the end points of bootstrapped values.
            maxSensitivityBootPlot = max(sensitivityBootSorted,[],2);
            minSensitivityBootPlot = min(sensitivityBootSorted,[],2);
            
            % If some points out of sensible range, mapping the points
            % within the range.
            limitMaxSensitivityBoot = log10(600);
            limitMinSensitivityBoot = 0;
            maxSensitivityBootPlot(maxSensitivityBootPlot>limitMaxSensitivityBoot) = limitMaxSensitivityBoot;
            minSensitivityBootPlot(minSensitivityBootPlot<limitMinSensitivityBoot) = limitMinSensitivityBoot;
            
            plot(sineFreqCyclesPerDegNumSorted,maxSensitivityBootPlot','g*','color',[0.1 0.7 0.1],'markerSize',7);
            plot(sineFreqCyclesPerDegNumSorted,minSensitivityBootPlot','g*','color',[0.1 0.7 0.1],'markerSize',7);
            
            %% Plot CSF.
            if (OneFigurePerSub)
                plot(smoothPlotSFVals,smoothPlotPreds,colorOptionsCSF{ff},'LineWidth',4);
            else
                % When fitting multiple smoothing params at once.
                if ~(nSmoothingParamsType == 1)
                    color = zeros(1,4);
                    color(1) = 1;
                    colorTransparency = 0.1;
                    for mm = 1:nSmoothingParamsType
                        color(4) = colorTransparency;
                        plot(smoothPlotSFVals,smoothPlotPreds(:,mm),'r-','color',color,'LineWidth',3);
                    end
                    % When fitting just one smoothing param.
                else
                    plot(smoothPlotSFVals,smoothPlotPreds,colorOptionsCSF{2},'LineWidth',4);
                end
            end
            
            % Plot CSF Boot if you did.
            if (BootstrapCSF)
                plot(smoothPlotSFVals, smoothPlotPredsBoot,'r-','color',[1 0 0 0.1],'LineWidth',2);
            end
            
            %% Plot AUC results if you want.
            if (PlotAUC)
                for aa = 1:nPointsCalAUC
                    plot(ones(1,2)*calAUCSFValsPlot(aa), [0 calAUCPredsPlot(aa)],'color',[1 1 0 0.1]);
                end
            end
            
            % Add details per each plot of the subject.
            if (~OneFigurePerSub)
                xlabel('Spatial Frequency (cpd)','fontsize',15);
                ylabel('Log Contrast Sensitivity','fontsize',15);
                xticks(sineFreqCyclesPerDegNumSorted);
                xticklabels(sineFreqCyclesPerDegNumSorted);
                yaxisRange = log10([10, 100, 200, 300, 400, 500, 600]);
                ylim(log10([1 600]));
                yticks(yaxisRange);
                ytickformat('%.2f');
                title(sprintf('CSF curve - Sub %s / Filter %s',subjectName,filterOptions{ff}),'fontsize',15);
                subtitle('Fitting was done on log CS - linear SF space');
                
                % Add legend.
                f_data = flip(get(gca, 'Children'));
                if exist('smoothPlotPredsBoot')
                    legend(f_data([1,2,6,7]),sprintf('Filter %s (PF)',filterOptions{ff}), sprintf('Filter %s (Boot)',filterOptions{ff}), ...
                        sprintf('CSF - %s',OptionSearchSmoothParam), sprintf('CSF Bootstrapped (N=%d)', nBootCSF),'fontsize',13,'location', 'northeastoutside');
                else
                    legend(f_data([1,2,4]),sprintf('Filter %s (PF)',filterOptions{ff}), sprintf('Filter %s (Boot)',filterOptions{ff}), ...
                        sprintf('CSF - %s',OptionSearchSmoothParam), 'fontsize',13,'location', 'northeastoutside');
                end
                
                % Make text Smoothing param for the plot.
                textSmoothingParam = sprintf('Smoothing parameter = %.8f', smoothingParam);
                
                % Make text AUC for the plot.
                confIntervals = 80;
                medianBootAUC = median(AUCBoot);
                lowBootCIAUC = prctile(AUCBoot,(100-confIntervals)/2);
                highBootCIAUC = prctile(AUCBoot,100 - (100-confIntervals)/2);
                textFittedAUC = sprintf('AUC = %.4f', AUC);
                textBootAUC = sprintf('Median boot AUC = %.4f (CI %d: %.4f/%.4f)', ...
                    medianBootAUC, confIntervals, lowBootCIAUC, highBootCIAUC);
                
                % Set the size of the texts in the plot.
                sizeTextOnPlot = 13;
                
                % We make equal spacing between the texts here.
                textFirstlineYLoc = 4;
                textThirdlineYLoc = 2;
                tempTextLoc = logspace(log10(textThirdlineYLoc),log10(textFirstlineYLoc),3);
                textSecondlineYLoc = tempTextLoc(2);
                
                % Add texts.
                if strcmp(OptionSearchSmoothParam,'type')
                    text(log10(3),log10(textFirstlineYLoc),...
                        sprintf('Smoothing parameter tested = (%.2f / %.5f / %.2f) \n',...
                        minSmoothingParamType,intervalSmoothingParamType,maxSmoothingParamType),...
                        'color','k','fontsize',sizeTextOnPlot);
                    text(log10(3),log10(textSecondlineYLoc),...
                        sprintf('Number of paramters tested = %d',nSmoothingParamsType),...
                        'color','k','fontsize',sizeTextOnPlot);
                else
                    text(3,log10(textFirstlineYLoc),textSmoothingParam,'color','k','fontsize',sizeTextOnPlot);
                    text(3,log10(textSecondlineYLoc),textFittedAUC,'color','k','fontsize',sizeTextOnPlot);
                    text(3,log10(textThirdlineYLoc),textBootAUC,'color','k','fontsize',sizeTextOnPlot);
                end
            end
            
            %% Save the CSF plot if you want.
            if (SaveCSFPlot)
                if ispref('SpatioSpectralStimulator',whichPref)
                    testFiledir = fullfile(getpref('SpatioSpectralStimulator',whichPref),...
                        subjectName,'CSF');
                end
                testFilename = fullfile(testFiledir, sprintf('%s_%s_%s','CSF', subjectName, filterOptions{ff}));
                testFileFormat = '.tiff';
                saveas(dataFig, append(testFilename,testFileFormat));
                disp('CSF plot has been saved successfully!');
            end
            
            %% Record the data. We will make a text summary file.
            subjectBigList{ss,ff} = subjectName;
            filterBigList{ss,ff} = filterOptions{ff};
            AUCBigList{ss,ff} = AUC;
            medianBootAUCBigList{ss,ff} = medianBootAUC;
            lowBootCIAUCBigList{ss,ff} = lowBootCIAUC;
            highBootCIAUCBigList{ss,ff} = highBootCIAUC;
            myCSValsBigList{ss,ff} = myCSVals;
            smoothingParamBigList{ss,ff} = smoothingParam;
            
            %% We will end the code here when we pick sujbect and filter.
            if (pickSubjectAndFilter)
                return;
            end
            
            % Key stroke to draw next plot.
            if (~OneFigurePerSub)
                if (WaitForKeyToPlot)
                    fprintf('\t Press a key to draw next plot! \n');
                    pause;
                    close all;
                end
            end
        end
        
        %% Save out the text summary file per each subject.
        if (RECORDTEXTSUMMARYPERSUB)
            if (~pickSubjectAndFilter)
                if ispref('SpatioSpectralStimulator',whichPref)
                    testFiledir = fullfile(getpref('SpatioSpectralStimulator',whichPref),subjectName,'CSF');
                end
                testFilename = fullfile(testFiledir,sprintf('AUC_Summary_%s.xlsx',subjectName));
                
                % Sort each data in a single column.
                nAUCPerSub = 5;
                NumCount_Summary = linspace(1,nAUCPerSub,nAUCPerSub)';
                Subject_Summary = subjectBigList(ss,:)';
                Filter_Summary = filterBigList(ss,:)';
                AUC_Summary = AUCBigList(ss,:)';
                medianBootAUC_Summary = medianBootAUCBigList(ss,:)';
                lowBootCIAUC_Summary = lowBootCIAUCBigList(ss,:)';
                highBootCIAUC_Summary = highBootCIAUCBigList(ss,:)';
                
                nCSPerFilter = length(myCSVals);
                for cc = 1:nCSPerFilter
                    CS_3cpd_Summary(cc)  = myCSValsBigList{ss,cc}(1);
                    CS_6cpd_Summary(cc)  = myCSValsBigList{ss,cc}(2);
                    CS_9cpd_Summary(cc)  = myCSValsBigList{ss,cc}(3);
                    CS_12cpd_Summary(cc) = myCSValsBigList{ss,cc}(4);
                    CS_18cpd_Summary(cc) = myCSValsBigList{ss,cc}(5);
                end
                
                SmoothingParam_Summary = smoothingParamBigList(ss,:)';
                
                % Make a table.
                tableAUCummary = table(NumCount_Summary,Subject_Summary,Filter_Summary,AUC_Summary,...
                    medianBootAUC_Summary,lowBootCIAUC_Summary,highBootCIAUC_Summary,...
                    CS_3cpd_Summary',CS_6cpd_Summary',CS_9cpd_Summary',CS_12cpd_Summary',CS_18cpd_Summary',...
                    SmoothingParam_Summary);
                
                % Change the variable name as desired.
                tableAUCummary.Properties.VariableNames = {'No', 'Subject', 'Filter', 'AUC', ...
                    'MedianBootAUC', 'LowBootCIAUC', 'HighBootCIAUC', ...
                    'LogSensitivity_3cpd','LogSensitivity_6cpd','LogSensitivity_9cpd','LogSensitivity_12cpd','LogSensitivity_18cpd',...
                    'SmoothingParameter'};
                
                % Write a table to the excel file.
                sheet = 1;
                range = 'B2';
                writetable(tableAUCummary,testFilename,'Sheet',sheet,'Range',range);
                disp('AUC summary table has been successfully created!');
            end
        end
        
        %% Add details per each plot of the subject.
        if (OneFigurePerSub)
            xlabel('Spatial Frequency (cpd)','fontsize',15);
            ylabel('Log Contrast Sensitivity','fontsize',15);
            
            xticks(sineFreqCyclesPerDegNumSorted);
            xticklabels(sineFreqCyclesPerDegNumSorted);
            
            yaxisRange = log10([10, 100, 200, 300, 400, 500, 600]);
            ylim(log10([1 600]));
            yticks(yaxisRange);
            ytickformat('%.2f');
            
            title(sprintf('CSF curve - Sub %s',subjectName),'fontsize',15);
            
            % Add legend.
            f_data = flip(get(gca, 'Children'));
            
            numSpaceLegend = 4;
            idxLegendRaw = linspace(1, 1+numSpaceLegend*(nSineFreqCyclesPerDeg-1), nSineFreqCyclesPerDeg);
            idxLegendBoot = linspace(2, 2+numSpaceLegend*(nSineFreqCyclesPerDeg-1), nSineFreqCyclesPerDeg);
            
            for ll = 1:nSineFreqCyclesPerDeg
                contentLegendRaw{ll} = sprintf('%s (PF)',filterOptions{ll});
                contentLegendBoot{ll} = sprintf('%s (Boot)',filterOptions{ll});
            end
            
            % Add legend when drawing one figure per each subject.
            legend(f_data([idxLegendRaw idxLegendBoot]), [contentLegendRaw contentLegendBoot], ...
                'fontsize', 13, 'location', 'northeast');
            
            % Save the CSF plot if you want.
            if (SaveCSFPlot)
                if ispref('SpatioSpectralStimulator',whichPref)
                    testFiledir = fullfile(getpref('SpatioSpectralStimulator',whichPref),subjectName,'CSF');
                end
                testFilename = fullfile(testFiledir, sprintf('%s_%s_%s_%s','CSF', subjectName, filterOptions{ff}));
                testFileFormat = '.tiff';
                saveas(dataFig, append(testFilename,testFileFormat));
                disp('CSF plot has been saved successfully!');
            end
            
            % Key stroke to draw next plot.
            if (WaitForKeyToPlot)
                disp('Press a key to draw next plot!');
                pause;
                close all;
            end
        end
    end
end
