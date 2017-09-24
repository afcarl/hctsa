function outputFileName = TS_normalize(normFunction,filterOptions,fileName_HCTSA,classVarFilter,subs)
% TS_normalize  Trims and normalizes data from an hctsa analysis.
%
% Reads in data from HCTSA.mat, writes a trimmed, normalized version to
% HCTSA_N.mat
% Normalization often involves a rescaling of each feature to the unit interval
% for visualization and clustering.
%
%---INPUTS:
% normFunction: String specifying how to normalize the data.
%
% filterOptions: Vector specifying thresholds for the minimum proportion of good
%                values required in a given row or column, in the form of a 2-vector:
%                [row proportion, column proportion]. If one of the filterOptions
%                is set to 1, will have no bad values in your matrix.
%
% fileName_HCTSA: Custom filename to import. Default is 'HCTSA.mat'.
%
% classVarFilter: whether to filter on zero variance of any given class (which
%                 can cause problems for many classification algorithms).
%
% subs [opt]: Only normalize and trim a subset of the data matrix. This can be used,
%             for example, to analyze just a subset of the full space, which can
%             subsequently be clustered and further subsetted using TS_cluster...
%             subs in the form {[rowrange],[columnrange]} (rows and columns to
%             keep, from HCTSA.mat).

% ------------------------------------------------------------------------------
% Copyright (C) 2016, Ben D. Fulcher <ben.d.fulcher@gmail.com>,
% <http://www.benfulcher.com>
%
% If you use this code for your research, please cite:
% B. D. Fulcher, M. A. Little, N. S. Jones, "Highly comparative time-series
% analysis: the empirical structure of time series and their methods",
% J. Roy. Soc. Interface 10(83) 20130048 (2013). DOI: 10.1098/rsif.2013.0048
%
% This work is licensed under the Creative Commons
% Attribution-NonCommercial-ShareAlike 4.0 International License. To view a copy of
% this license, visit http://creativecommons.org/licenses/by-nc-sa/4.0/ or send
% a letter to Creative Commons, 444 Castro Street, Suite 900, Mountain View,
% California, 94041, USA.
% ------------------------------------------------------------------------------

% --------------------------------------------------------------------------
%% Check Inputs
% --------------------------------------------------------------------------
if nargin < 1 || isempty(normFunction)
    fprintf(1,'Using the default, scaled quantile-based sigmoidal transform: ''scaledRobustSigmoid''\n')
    normFunction = 'scaledRobustSigmoid';
end

if nargin < 2 || isempty(filterOptions)
    filterOptions = [0.70, 1];
    % By default remove less than 70%-good-valued time series, & then less than
    % 100%-good-valued operations.
end
if any(filterOptions > 1)
    error('Set filterOptions as a length-2 vector with elements in the unit interval');
end
fprintf(1,['Removing time series with more than %.2f%% special-valued outputs\n' ...
            'Removing operations with more than %.2f%% special-valued outputs\n'], ...
            (1-filterOptions(1))*100,(1-filterOptions(2))*100);

% By default, work HCTSA.mat, e.g., generated by SQL_retrieve or TS_init
if nargin < 3 || isempty(fileName_HCTSA)
    fileName_HCTSA = 'HCTSA.mat';
end

if nargin < 4
    classVarFilter = false; % don't filter on individual class variance > 0 by default
end

if nargin < 5
    % Empty by default, i.e., don't subset:
    subs = {};
end

% --------------------------------------------------------------------------
%% Read data from local files
% --------------------------------------------------------------------------

% Load data:
[TS_DataMat,TimeSeries,Operations,whatDataFile] = TS_LoadData(fileName_HCTSA);
load(whatDataFile,'TS_Quality','MasterOperations');

% First check that fromDatabase exists (for back-compatability)
fromDatabase = TS_GetFromData(fileName_HCTSA,'fromDatabase');
if isempty(fromDatabase)
    fromDatabase = true; % (legacy)
end

% Check that we have the groupNames if already assigned labels
groupNames = TS_GetFromData(fileName_HCTSA,'groupNames');
if isempty(groupNames)
    groupnames = {};
end

% Maybe we kept the git repository info
gitInfo = TS_GetFromData(fileName_HCTSA,'gitInfo');

%-------------------------------------------------------------------------------
% In this script, each of these pieces of data (from the database) will be
% trimmed and normalized, and then saved to HCTSA_N.mat
%-------------------------------------------------------------------------------

% ------------------------------------------------------------------------------
%% Subset using given indices, subs
% ------------------------------------------------------------------------------
if ~isempty(subs)
    kr0 = subs{1}; % rows to keep (0)
    if ~isempty(kr0)
        fprintf(1,'Filtered down time series by given subset; from %u to %u.\n',...
                    size(TS_DataMat,1),length(kr0));
        TS_DataMat = TS_DataMat(kr0,:);
        TS_Quality = TS_Quality(kr0,:);
        TimeSeries = TimeSeries(kr0);
    end

    kc0 = subs{2}; % columns to keep (0)
    if ~isempty(kc0)
        fprintf(1,'Filtered down operations by given subset; from %u to %u.\n',...
            size(TS_DataMat,2),length(kc0));
        TS_DataMat = TS_DataMat(:,kc0);
        TS_Quality = TS_Quality(:,kc0);
        Operations = Operations(kc0);
    end
end

% --------------------------------------------------------------------------
%% Trim down bad rows/columns
% --------------------------------------------------------------------------

% (i) NaNs in TS_DataMat mean values uncalculated in the matrix.
TS_DataMat(~isfinite(TS_DataMat)) = NaN; % Convert all nonfinite values to NaNs for consistency
% Need to also incorporate knowledge of bad entries in TS_Quality and filter these out:
TS_DataMat(TS_Quality > 0) = NaN;
fprintf(1,'\nThere are %u special values in the data matrix.\n',sum(TS_Quality(:) > 0));
percGood_rows = mean(~isnan(TS_DataMat),2)*100;
fprintf(1,'(pre-filtering): Time series vary from %.2f--%.2f%% good values\n',...
                min(percGood_rows),max(percGood_rows));
percGood_cols = mean(~isnan(TS_DataMat),1)*100;
fprintf(1,'(pre-filtering): Features vary from %.2f--%.2f%% good values\n',...
                min(percGood_cols),max(percGood_cols));

% Now that all bad values are NaNs, and we can get on with the job of filtering them out

% (*) Filter based on proportion of bad entries. If either threshold is 1,
% the resulting matrix is guaranteed to be free from bad values entirely.

% Filter time series (rows)
keepRows = filterNaNs(TS_DataMat,filterOptions(1),'time series');
if any(~keepRows)
    fprintf(1,'Time series removed: %s.\n\n',BF_cat({TimeSeries(~keepRows).Name},','));
    TS_DataMat = TS_DataMat(keepRows,:);
    TS_Quality = TS_Quality(keepRows,:);
    TimeSeries = TimeSeries(keepRows);
end

% Filter operations (columns)
keepCols = filterNaNs(TS_DataMat',filterOptions(2),'operations');
if any(~keepCols)
    % fprintf(1,'Operations removed: %s.\n\n',BF_cat({Operations(~keepCols).Name},','));
    TS_DataMat = TS_DataMat(:,keepCols);
    TS_Quality = TS_Quality(:,keepCols);
    Operations = Operations(keepCols);
end

% --------------------------------------------------------------------------
%% Filter out operations that are constant across the time-series dataset
%% And time series with constant feature vectors
% --------------------------------------------------------------------------
if size(TS_DataMat,1) > 1 % otherwise just a single time series remains and all will be constant!
    bad_op = (nanstd(TS_DataMat) < 10*eps);

    if all(bad_op)
        error('All %u operations produced constant outputs on the %u time series?!',...
                            length(bad_op),size(TS_DataMat,1))
    elseif any(bad_op)
        fprintf(1,'Removed %u operations with near-constant outputs: from %u to %u.\n',...
                         sum(bad_op),length(bad_op),sum(~bad_op));
        TS_DataMat = TS_DataMat(:,~bad_op);
        TS_Quality = TS_Quality(:,~bad_op);
        Operations = Operations(~bad_op);
    else
        fprintf(1,'No operations had near-constant outputs on the dataset\n');
    end
end

%-------------------------------------------------------------------------------
% Filter on class variance
%-------------------------------------------------------------------------------
if classVarFilter
    if ~isfield(TimeSeries,'Group')
        fprintf(1,'Group labels not assigned to time series, so cannot filter on class variance\n');
    end
    numClasses = length(unique([TimeSeries.Group]));
    classVars = zeros(numClasses,size(TS_DataMat,2));
    for i = 1:numClasses
        classVars(i,:) = nanstd(TS_DataMat([TimeSeries.Group]==i,:));
    end
    zeroClassVar = any(classVars < 10*eps,1);
    if all(zeroClassVar)
        error('All %u operations produced near-constant class-wise outputs?!',...
                            length(zeroClassVar),size(TS_DataMat,1))
    elseif any(zeroClassVar)
        fprintf(1,'Removed %u operations with near-constant class-wise outputs: from %u to %u.\n',...
                     sum(zeroClassVar),length(zeroClassVar),sum(~zeroClassVar));
        TS_DataMat = TS_DataMat(:,~zeroClassVar);
        TS_Quality = TS_Quality(:,~zeroClassVar);
        Operations = Operations(~zeroClassVar);
    end
end

%-------------------------------------------------------------------------------
%% Update the labels after filtering
%-------------------------------------------------------------------------------
% At this point, you could check to see if any master operations are no longer
% pointed to and recalibrate the indexing, but I'm not going to bother.

if length(TimeSeries)==1
    % When there is only a single time series, it doesn't actually make sense to normalize
    error('Only a single time series remains in the dataset -- normalization cannot be applied');
end

fprintf(1,'\n(post-filtering): %u special-valued entries (%4.2f%%) remain in the %ux%u data matrix.\n',...
            sum(isnan(TS_DataMat(:))), ...
            sum(isnan(TS_DataMat(:)))/length(TS_DataMat(:))*100,...
            size(TS_DataMat,1),size(TS_DataMat,2));

if sum(isnan(TS_DataMat(:)) > 0)
    percGood_rows = mean(~isnan(TS_DataMat),2)*100;
    fprintf(1,'(post-filtering): Time series vary from %.2f--%.2f%% good values\n',...
                                min(percGood_rows),max(percGood_rows));
    percGood_cols = mean(~isnan(TS_DataMat),1)*100;
    fprintf(1,'(post-filtering): Features vary from %.2f--%.2f%% good values\n',...
                                min(percGood_cols),max(percGood_cols));
end
fprintf(1,'\n');

% --------------------------------------------------------------------------
%% Filtering done, now apply the normalizing transformation
% --------------------------------------------------------------------------

if ismember(normFunction,{'nothing','none'})
    fprintf(1,'You specified ''%s'', so NO NORMALIZING IS ACTUALLY BEING DONE!!!\n',normFunction);
else
    % No training subset specified
    fprintf(1,'Normalizing a %u x %u object. Please be patient...\n',...
                            length(TimeSeries),length(Operations));
    TS_DataMat = BF_NormalizeMatrix(TS_DataMat,normFunction);
    fprintf(1,'Normalized! The data matrix contains %u special-valued elements.\n',sum(isnan(TS_DataMat(:))));
end

% --------------------------------------------------------------------------
%% Remove bad entries
% --------------------------------------------------------------------------
% Bad entries after normalizing can be due to feature vectors that are
% constant after e.g., the sigmoid transform -- a bit of a weird thing to do if
% pre-filtering by percentage...

nanCol = (mean(isnan(TS_DataMat))==1);
if all(nanCol) % all columns are NaNs
    error('After normalization, all columns were bad-values... :(');
elseif any(nanCol) % there are columns that are all NaNs
    TS_DataMat = TS_DataMat(:,~nanCol);
    TS_Quality = TS_Quality(:,~nanCol);
    Operations = Operations(~nanCol);
    fprintf(1,'We just removed %u all-NaN columns introduced from %s normalization.\n',...
                        sum(nanCol),normFunction);
end

% --------------------------------------------------------------------------
%% Make sure the operations are still good
% --------------------------------------------------------------------------
% Check again for ~constant columns after normalization
kc = (nanstd(TS_DataMat) < 10*eps);
if any(kc)
    TS_DataMat = TS_DataMat(:,~kc);
    TS_Quality = TS_Quality(:,~kc);
    Operations = Operations(~kc);
    fprintf(1,'%u operations had near-constant outputs after filtering: from %u to %u.\n', ...
                    sum(~kc),length(kc),sum(kc));
end

fprintf(1,'%u bad entries (%4.2f%%) in the %ux%u data matrix.\n', ...
            sum(isnan(TS_DataMat(:))),sum(isnan(TS_DataMat(:)))/length(TS_DataMat(:))*100, ...
            size(TS_DataMat,1),size(TS_DataMat,2));

% ------------------------------------------------------------------------------
% Set default clustering details
% ------------------------------------------------------------------------------
ts_clust = struct('distanceMetric','none','Dij',[],...
                'ord',1:size(TS_DataMat,1),'linkageMethod','none');
op_clust = struct('distanceMetric','none','Dij',[],...
                'ord',1:size(TS_DataMat,2),'linkageMethod','none');

% --------------------------------------------------------------------------
%% Save results to file
% --------------------------------------------------------------------------

% Make a structure with statistics on normalization:
% Save the codeToRun, so you can check the settings used to run the normalization
% At the moment, only saves the first two arguments
codeToRun = sprintf('TS_normalize(''%s'',[%f,%f])',normFunction, ...
                                        filterOptions(1),filterOptions(2));
normalizationInfo = struct('normFunction',normFunction,'filterOptions', ...
                                    filterOptions,'codeToRun',codeToRun);

outputFileName = [fileName_HCTSA(1:end-4),'_N.mat'];

fprintf(1,'Saving the trimmed, normalized data to %s...',outputFileName);
save(outputFileName,'TS_DataMat','TS_Quality','TimeSeries','Operations', ...
        'MasterOperations','fromDatabase','groupNames','normalizationInfo',...
        'gitInfo','ts_clust','op_clust','-v7.3');
fprintf(1,' Done.\n');

%-------------------------------------------------------------------------------
function keepInd = filterNaNs(XMat,nan_thresh,objectName)
    % Returns an index of rows of XMat with at least nan_thresh good values.

    if nan_thresh == 0
        keepInd = true(size(XMat,1));
        return
    else
        propNaN = mean(isnan(XMat),2); % proportion of NaNs across rows
        keepInd = (1-propNaN >= nan_thresh);
        if all(~keepInd)
            error('No %s had more than %4.2f%% good values.\nSet a more lenient threshold.',...
                                objectName,nan_thresh*100)
        end
        if all(keepInd)
            fprintf(1,['All %u %s have greater than %4.2f%% good values.' ...
                            ' Keeping them all.\n'], ...
                            length(keepInd),objectName,nan_thresh*100);
        else
            fprintf(1,['Removing %u %s with fewer than %4.2f%% good values:'...
                        ' from %u to %u.\n'],sum(~keepInd),objectName,...
                        nan_thresh*100,length(keepInd),sum(keepInd));
        end
    end
end
%-------------------------------------------------------------------------------

end
