function [paramsFitted, ...
    thresholdFitted, thresholdFittedBoot, medianThresholdBoot, lowThresholdBoot, highThresholdBoot,...
    slopeFitted,medianSlopeBoot,lowSlopeBoot,highSlopeBoot, ...
    legendHandles] = FitPFToData(stimLevels,pCorrect,options)
% Fit Psychometric function to the given data.
%
% Syntax:
%    [paramsFitted,...
%      thresholdFitted, medianThresholdBoot,lowThresholdBoot,highSlopeBoot ...
%      slopeFitted,medianSlopeBoot,lowSlopeBoot,highSlopeBoot] = FitPFToData(stimLevels,pCorrect)
%
% Description:
%    This fits Psychometric function to the data given as an input. You can
%    choose PF either Weibull or Logistic.
%
% Inputs:
%    stimLevels -                 Array of the stimulus levels.
%    pCorrect -                   Array of percentage correct per each
%                                 stimulus level. This should be the same
%                                 size of the stimLevels.
%
% Outputs:
%    paramsFitted -               Parameters found from PF fitting. It's in
%                                 the format of the array [threshold slope
%                                 guess lapse]. You can choose which one to
%                                 be free/not free parameters.
%    thresholdFitted -            Threshold at criterion
%    thresholdFittedBoot -        All bootstrapped values.
%    medianThresholdBoot -        Median of boostrapped threshold
%    lowThresholdBoot -           Low end of bootstrapped CI
%    highThresholdBoot -          High end of bootstrapped CI
%    slopeFitted -                Fit slope
%    medianSlopeBoot -            Median of bootstrapped slopes
%    lowSlopeBoot -               Low end of bootstrapped slope CI
%    highSlopeBoot -              High end of bootstrapped slope CI
%    legendHandles -              Vector of plot handles so calling routine
%                                 can make a sensible legend.
%
% Optional key/value pairs:
%    PF -                         Default to 'weibull'. Choose the function
%                                 to fit the data either 'weibull' or
%                                 'logistic'.
%    paramsFree -                 Default to [1 1 0 1]. This decides which
%                                 parameters to be free. Array represents
%                                 [threshold slope guess lapse]. Each can
%                                 be set either 0 or 1, where 0 = fixed
%                                 1 = free.
%    beta -                       Set of slope parameters to fit for.  Each
%                                 of these is fixed and the best fit over
%                                 the set is used.  This allows us to
%                                 control the slope range. When this is not
%                                 empty, the second entry of params free
%                                 above is ignored, and the fit is done for
%                                 the passed set with best returned.
%                                 Default is empty.
%    nTrials -                    Default to 20. The number of trials
%                                 conducted per each stimulus level.
%    thresholdCriterion -         Default to 0.81606. This is the value of
%                                 pCorrect as a criteria to find threshold.
%    newFigureWindow -            Default to true. Make a new figure window
%                                 to plot the results. If you want to plot
%                                 multiple threshold results in a subplot,
%                                 set this to false and do so.
%    pointSize                  - Default to 100 each. Set the size of data
%                                 point on the scatter plot.
%    axisLog                    - Default to true. If it sets to true, plot
%                                 the graph with x-axis on log space.
%    questPara                  - Default to blank. Add Quest fit if this
%                                 is not empty.Row vector or matrix of
%                                 parameters.
%                                 threshold  Threshold in log unit
%                                 slope      Slope
%                                 guess      Guess rate
%                                 lapse      Lapse rate
%                                 Parameterization matches the Mathematica
%                                 code from the Watson QUEST+ paper.
%    addLegend                  - Default to true. Add legend when it sets
%                                 to true.
%    nBootstraps                - Number of bootstraps to run.  0 means no
%                                 bootstrapping. Default 0.
%    bootConfInterval           - Size of bootstrapped confidence interval.
%                                 Default 0.8.
%    verbose -                  - Default to true. Boolean. Controls
%                                 plotting and printout.
%
% See also:
%    N/A

% History:
%   02/25/22  dhb, smo         - Started on it.
%   03/14/22  smo              - Added a plotting option to make different
%                                marker size over different number of
%                                trials.
%   11/14/22  dhb              - Bootstrapping
%   02/06/23  smo              - Now print out all bootstrap values.

%% Set parameters.
arguments
    stimLevels
    pCorrect
    options.PF = 'weibull'
    options.paramsFree (1,4) = [1 1 0 1]
    options.beta = []
    options.nTrials (1,1) = 20
    options.thresholdCriterion (1,1) = 0.81606
    options.newFigureWindow (1,1) = true
    options.pointSize = ones(1,length(stimLevels))*100
    options.axisLog (1,1) = true
    options.questPara = []
    options.addLegend (1,1) = true
    options.nBootstraps = 0
    options.bootConfInterval = 0.8
    options.verbose (1,1) = true
end

%% Check the size of the input parameters.
if (~any(size(stimLevels) == size(pCorrect)))
    error('Stimulus level and pCorrect array size does not match!');
end

%% Set PF fitting type here.
switch options.PF
    case 'weibull'
        PF = @PAL_Weibull;
    case 'logistic'
        PF = @PAL_Logistic
    otherwise
end

%% Fitting PF.
%
% Set up the PF fitting (requires Palamedes toolbox).  Note that the
% catch trials are added in here in the call to the fit.
nTrialsPerContrast = options.nTrials * ones(size(stimLevels));
nCorrect = round(pCorrect .* nTrialsPerContrast);

% Set an initial search parameters, with
% gridded slope (aka beta).  The grid search
% is only done if options.beta is empty.
searchGrid.alpha = mean(stimLevels);
searchGrid.beta = 10.^(-2:0.01:2);
searchGrid.gamma = 0.5;
searchGrid.lambda = 0.01;
lapseLimits = [0 0.05];

% PF fitting happens here. Search over passed
% list of possible slopes
if (~isempty(options.beta))
    paramsFreeUse = options.paramsFree;
    paramsFreeUse(2) = 0;
    for ss = 1:length(options.beta)
        searchGridUse = searchGrid;
        searchGridUse.beta = options.beta(ss);
        [paramsFittedList(ss,:) LL(ss)] = PAL_PFML_Fit(stimLevels, nCorrect, ...
            nTrialsPerContrast, searchGridUse, paramsFreeUse, PF, 'lapseLimits', lapseLimits);
    end
    [~,index] = max(LL);
    paramsFitted = paramsFittedList(index,:);
    PLOT_SLOPELL = false;
    if (PLOT_SLOPELL)
        theFig = gcf;
        llfig = figure; clf; hold on
        plot(options.beta,LL,'ro');
        figure(theFig);
        pause;
        close(llfig);
    end
    
    % Otherwise use Palamedes grid search
else
    paramsFitted = PAL_PFML_Fit(stimLevels, nCorrect, ...
        nTrialsPerContrast, searchGrid, paramsFree, PF, 'lapseLimits', lapseLimits);
end
thresholdFitted = PF(paramsFitted, options.thresholdCriterion, 'inv');
slopeFitted = paramsFitted(2);

% Bootstrap fits
if (options.nBootstraps > 0)
    paramsFittedBoot = zeros(options.nBootstraps,4);
    for bb = 1:options.nBootstraps
        % Bootstrap the data
        nCorrectBoot = zeros(size(nCorrect));
        nCorrectCross1 = zeros(size(nCorrect));
        nCorrectCross2 = zeros(size(nCorrect));
        nTrialsPerContrastCross1 = zeros(size(nCorrect));
        nTrialsPerContrastCross2 = zeros(size(nCorrect));
        for cc = 1:length(nTrialsPerContrast)
            trialsBoot = zeros(1,nTrialsPerContrast(cc));
            trialsBoot(1:nCorrect(cc)) = 1;
            index = randi(nTrialsPerContrast(cc),1,nTrialsPerContrast(cc));
            nCorrectBoot(cc) = sum(trialsBoot(index));
            trialsShuffle = Shuffle(trialsBoot);
            splitN = round(length(trialsShuffle)/2);
            nCorrectCross1(cc) = sum(trialsShuffle(1:splitN));
            nCorrectCross2(cc) = sum(trialsShuffle((splitN+1):end));
            nTrialsPerContrastCross1(cc) = length(trialsShuffle(1:splitN));
            nTrialsPerContrastCross2(cc) = length(trialsShuffle((splitN+1):end));
        end
        
        % Fit the bootstrap data in same way we fit actual data
        if (~isempty(options.beta))
            paramsFreeUse = options.paramsFree;
            paramsFreeUse(2) = 0;
            for ss = 1:length(options.beta)
                searchGridUse = searchGrid;
                searchGridUse.beta = options.beta(ss);
                [paramsFittedList(ss,:) LL(ss)] = PAL_PFML_Fit(stimLevels, nCorrectBoot, ...
                    nTrialsPerContrast, searchGridUse, paramsFreeUse, PF, 'lapseLimits', lapseLimits);
            end
            [~,index] = max(LL);
            paramsFittedBoot(bb,:) = paramsFittedList(index,:);
        else
            paramsFittedBoot(bb,:) = PAL_PFML_Fit(stimLevels, nCorrectBoot, ...
                nTrialsPerContrast, searchGrid, paramsFree, PF, 'lapseLimits', lapseLimits);
        end
        
        % Grab bootstrapped threshold
        thresholdFittedBoot(bb) = PF(paramsFittedBoot(bb,:), options.thresholdCriterion, 'inv');
    end
    medianThresholdBoot = median(thresholdFittedBoot);
    lowThresholdBoot = prctile(thresholdFittedBoot,100*(1-options.bootConfInterval)/2);
    highThresholdBoot = prctile(thresholdFittedBoot,100-100*(1-options.bootConfInterval)/2);
    medianSlopeBoot = median(paramsFittedBoot(:,2));
    lowSlopeBoot = prctile(paramsFittedBoot(:,2),100*(1-options.bootConfInterval)/2);
    highSlopeBoot = prctile(paramsFittedBoot(:,2),100-100*(1-options.bootConfInterval)/2);
else
    paramsFittedBoot = [];
    thresholdFittedBoot = [];
    medianThresholdBoot = [];
    lowThresholdBoot = [];
    highThresholdBoot = [];
    medianSlopeBoot = [];
    lowSlopeBoot = [];
    highSlopeBoot = [];
end

% Make a smooth curves with finer stimulus levels.
nFineStimLevels = 1000;
fineStimLevels = linspace(0, max(stimLevels), nFineStimLevels);
smoothPsychometric = PF(paramsFitted, fineStimLevels);

if (options.verbose)
    fprintf('Threshold was found at %.4f (linear unit) \n', thresholdFitted);
end

%% Plot the results if you want.
if (options.verbose)
    if (options.newFigureWindow)
        figure; clf; hold on;
    end
    
    % Plot all experimental data (gray points).
    %
    % Marker size will be different over the number of the trials per each
    % test point.
    %
    % Plot it on log space if you want.
    if (options.axisLog)
        stimLevelsPlot = log10(stimLevels);
        thresholdFittedLog = log10(thresholdFitted);
        fineStimLevelsPlot = log10(fineStimLevels);
    else
        stimLevelsPlot = stimLevels;
        fineStimLevelsPlot = fineStimLevels;
    end
    
    % Plot bootstraps
    for bb = 1:options.nBootstraps
        smoothPsychometricBoot = PF(paramsFittedBoot(bb,:), fineStimLevels);
        h_bsfit = plot(fineStimLevelsPlot,smoothPsychometricBoot,'Color',[0.9 0.8 0.8],'LineWidth',0.5);
    end
    
    % Plot best fit here.
    h_data = scatter(stimLevelsPlot, pCorrect, options.pointSize,...
        'MarkerEdgeColor', zeros(1,3), 'MarkerFaceColor', ones(1,3) * 0.5, 'MarkerFaceAlpha', 0.5);
    h_pffit = plot(fineStimLevelsPlot,smoothPsychometric,'r','LineWidth',3);
    
    % Mark the threshold point (red point).
    if(options.axisLog)
        h_thresh = plot(thresholdFittedLog,options.thresholdCriterion,'ko','MarkerFaceColor','r','MarkerSize',12);
        if (options.nBootstraps > 0)
            h_bsthresh = errorbarX(log10(medianThresholdBoot),options.thresholdCriterion,log10(medianThresholdBoot)-log10(lowThresholdBoot),log10(highThresholdBoot)-log10(medianThresholdBoot),'go');
            set(h_bsthresh,'MarkerSize',9); set(h_bsthresh,'MarkerFaceColor','g'); set(h_bsthresh,'MarkerEdgeColor','g'); set(h_bsthresh,'LineWidth',3);
        end
        xlabel('Contrast (log)', 'FontSize', 15);
    else
        h_thresh = plot(thresholdFitted,options.thresholdCriterion,'ko','MarkerFaceColor','r','MarkerSize',12);
        if (options.nBootstraps > 0)
            h_bsthresh = errorbarX(medianThresholdBoot,options.thresholdCriterion,medianThresholdBoot-lowThresholdBoot,highThresholdBoot-medianThresholdBoot,'go');
            set(h_bsthresh,'MarkerSize',9); set(h_bsthresh,'MarkerFaceColor','g'); set(h_bsthresh,'MarkerEdgeColor','g'); set(h_bsthresh,'LineWidth',3);
        end
        xlabel('Contrast', 'FontSize', 15);
    end
    ylabel('pCorrect', 'FontSize', 15);
    ylim([0 1]);
    if (~isempty(options.beta))
        if (options.nBootstraps > 0)
            title({sprintf('Threshold: %0.4f, [%0.4f (%0.4f, %0.4f, %d%%]',...
                thresholdFitted,medianThresholdBoot,lowThresholdBoot,highThresholdBoot,round(100*options.bootConfInterval)) ; ...
                sprintf('Slope range: %0.4f to %0.4f',min(options.beta),max(options.beta)); ...
                sprintf('Slope: %0.4f, [%0.4f (%0.4f, %0.4f, %d%%]',...
                slopeFitted,medianSlopeBoot,lowSlopeBoot,highSlopeBoot,round(100*options.bootConfInterval))});
        else
            title({sprintf('Threshold: %0.4f',thresholdFitted); sprintf('Slope: %0.4f',slopeFitted); ...
                sprintf('Slope range: %0.4f to %0.4f',min(options.beta),max(options.beta))})
        end
    else
        if (options.nBootstraps > 0)
            title({sprintf('Threshold: %0.4f, [%0.4f (%0.4f, %0.4f, %d%%]',...
                thresholdFitted,medianThresholdBoot,lowThresholdBoot,highThresholdBoot,round(100*options.bootConfInterval)) ; ...
                sprintf('Slope: %0.4f, [%0.4f (%0.4f, %0.4f, %d%%]',...
                slopeFitted,medianSlopeBoot,lowSlopeBoot,highSlopeBoot,round(100*options.bootConfInterval))});
        else
            title({sprintf('Threshold: %0.4f',thresholdFitted); sprintf('Slope: %0.4f',slopeFitted)})
        end
    end
    
    %% Get QuestPlus prediction and add to plot.
    %
    % Calculate QuestPlus prediction here and plot it.
    if ~isempty(options.questPara)
        predictedQuestPlus = qpPFWeibullLog(fineStimLevelsPlot',options.questPara);
        h_quest = plot(fineStimLevelsPlot,predictedQuestPlus(:,2),'k--','LineWidth',3);
    end
    
    % Add legend if you want.
    if (options.nBootstraps > 0)
        if ~isempty(options.questPara)
            legendHandles = [h_data h_pffit h_thresh h_bsthresh(2) h_bsthresh(1) h_quest];
        else
            legendHandles = [h_data h_pffit h_thresh h_bsthresh(2) h_bsthresh(1)];
        end
        if (options.addLegend)
            if ~isempty(options.questPara)
                legend(legendHandles, 'Data','PF-fit','PF-Threshold','BS-Threshold','BS-ConfInt', 'Quest-fit',...
                    'FontSize', 12, 'location', 'southeast');
            else
                legend(legendHandles, 'Data','PF-fit','PF-Threshold','BS-Threshold','BS-ConfInt', ...
                    'FontSize', 12, 'location', 'southeast');
            end
        end
    else
        if ~isempty(options.questPara)
            legendHandles = [h_data h_pffit h_thresh h_quest];
        else
            legendHandles = [h_data h_pffit h_thresh];
        end
        if (options.addLegend)
            if ~isempty(options.questPara)
                legend(legendHandles, 'Data','PF-fit','PF-Threshold','Quest-fit',...
                    'FontSize', 12, 'location', 'southeast');
            else
                legend(legendHandles, 'Data','PF-fit','PF-Threshold', ...
                    'FontSize', 12, 'location', 'southeast');
            end
        end
    end
    
    drawnow;
    
end
