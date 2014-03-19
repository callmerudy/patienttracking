%Script for predicting patient lactate value usign K-means
clear all;close all;clc


%The dataset, lact_db, will contain the features described by the variable
%'column_names, all measurements are from the interpolated series.
%The database is expected to have the input features starting after
%'lact_dxx'

%load lactate-kmeans-dataset-6hours-smoothed % 0.5 hours smoothed data, default
load realTime-lactate-interpolated-dataset-0hours-smoothed % 0.5 hours smoothed data, default

%Load smoothed timed series prefix the variables accordingly
smooth_set=fliplr([0 3 5 13 23]);  %higher values have less data
lact_db_init=lact_db; %Load to get intial parameter settings
target=raw_lact_measurements;
pid_init=lact_db(:,1);
unique_pid=unique(pid_init);
Npid=length(unique_pid);
Ndb=length(lact_db);

Nsmooth=length(smooth_set);
for s=1:Nsmooth
    eval(['load realTime-lactate-interpolated-dataset-'   num2str(smooth_set(s)) 'hours-smoothed'])
    eval(['lact_db_' num2str(smooth_set(s)) '=lact_db;'])
end


%Normalize Urine by weight (apply quotient rule to derivative)
tm_ind=find(strcmp(column_names,'tm')==1);
urine_ind=find(strcmp(column_names,'urine_val')==1);
weight_ind=find(strcmp(column_names,'weight_val')==1);
urine_dx_ind=find(strcmp(column_names,'urine_dx')==1);
weight_dx_ind=find(strcmp(column_names,'weight_dx')==1);

%Update smooth set to have default case and normalize urine over all interpolated sets
for s=1:Nsmooth
    str=num2str(smooth_set(s));
    eval(['lact_db_' str  '(:,urine_ind)=lact_db_' str '(:,urine_ind)./lact_db_' str '(:,weight_ind);'])
    eval(['urine_dx=lact_db_' str '(:,urine_dx_ind);'])
    eval(['weigth_dx=lact_db_' str '(:,weight_dx_ind);'])
    eval(['urine_dx= ( urine_dx.*lact_db_' str '(:,weight_ind) - lact_db_' str '(:,urine_ind).*weigth_dx)./(lact_db_' str '(:,weight_ind).^2);'])
    eval(['lact_db_' str '(:,urine_dx_ind)=urine_dx;'])
end


%For now only use these columns (other features will be discarded
use_col={'map_val','map_dx','map_var','ageNormalized_hr_val','ageNormalized_hr_dx','ageNormalized_hr_var','urine_val','urine_dx',...
    'urine_var','weight_val','weight_dx','pressor_val','cardiacOutput_val','cardiacOutput_dx','cardiacOutput_var'...
    'hr_val','hr_dx','hr_var'};

%use_col={'map_val','ageNormalized_hr_val','urine_val','urine_var','weight_dx','pressor_val','cardiacOutput_val'};
Ncol=length(use_col);
del=[1:length(column_names)];
for n=1:Ncol
    ind=find(strcmp(column_names,use_col{n})==1);
    del(ind)=NaN;
end
del(isnan(del))=[];
if(~isempty(del))
    column_names(del)=[];
    for s=1:Nsmooth
        eval(['tmp_pid=' 'lact_db_' num2str(smooth_set(s)) '(:,1);'])
        eval(['lact_db_' num2str(smooth_set(s)) '(:,del)=[];'])
        checkSum=sum(tmp_pid~=pid_init);
        if(checkSum>0)
            error('DB pids do not match.')
        end
    end
end

%Limit all datasets to the points constrained in the highest smoothed
%series
eval(['lact_db=lact_db_' num2str(smooth_set(1)) ';']) %initialize db

for s=2:Nsmooth
    %Append all smoothed sets together
    eval(['tmp_lact_db=lact_db_' num2str(smooth_set(s)) ';'])
    lact_db=[lact_db tmp_lact_db];
end

%Replace each NaN in the input features by their mean
Mcol=length(lact_db(1,:));
for nf=1:Mcol
    nans=find(isnan(lact_db(:,nf))==1);
    if(~isempty(nan))
        tmp_mean=nanmean(lact_db(:,nf));
        lact_db(nans,nf)=tmp_mean;
    end
end

%Partition the dataset into 3 parts for 3x validation
%The N-fold validation is done in terms of number of patients, not number
%of measurements (which may be dependent).
%TODO: The sets should have no points from the same patient, or points from
%the same patient that are sufficiently far apart to be deemed independent
% (say, 6 hours).

Nfold=3;
NCrossVal=ceil(Npid/Nfold)*Nfold;

%Shuffle the unique patients
shuffled_pids=unique_pid(randperm(Npid));

%Columns are the Nfold, rows are the patients (not lactate measurements)
if(Npid <NCrossVal)
    shuffled_pids(NCrossVal)=NaN;
end
shuffled_pids=reshape(shuffled_pids,[NCrossVal/Nfold Nfold]);

crossPerf=zeros(Nfold,1)+NaN;
Ntest=NCrossVal/Nfold;
Ntrain=Ntest*2;

for n=1:Nfold
    
    %Set test, training and validation data (MATLAB's NN Toolbox will take care
    %of the training and validation steps).
    test_unique_pid=shuffled_pids(:,n);
    train_unique_pid=setdiff(shuffled_pids(:),test_unique_pid);
    
    %Generate the test and training datasets & targets
    testData=zeros(Ntest,Mcol)+NaN;
    trainData=zeros(Ntrain,Mcol)+NaN;
    
    testTarget=zeros(Ntest,1)+NaN;
    trainTarget=zeros(Ntest,1)+NaN;
    test_ind=1;
    train_ind=1;
    old_pid=0;
    for t=1:Ndb
        tmp_pid=pid_init(t);
        if(tmp_pid ~= old_pid)
            %Use this to improve performance for repeated measurements on
            %same patient
            isTest=NaN;
            if(~isempty(find(test_unique_pid == tmp_pid)))
                isTest=1;
            elseif(~isempty(find(train_unique_pid == tmp_pid)))
                isTest=0;
            else
                error('Unmatched id!!')
            end
            old_pid=tmp_pid;
        end
 
        if(isTest)
            testData(test_ind,:)=lact_db(t,:);
            testTarget(test_ind)=target(t);
            test_ind=test_ind+1;
        else
            trainData(train_ind,:)=lact_db(t,:);
            trainTarget(train_ind)=target(t);
            train_ind=train_ind+1;
        end
    end
    
    %Remove any NaN points
    del_ind=find(isnan(testTarget)==1);
    testTarget(del_ind)=[];
    testData(del_ind,:)=[];
    
    del_ind=find(isnan(trainTarget)==1);
    trainTarget(del_ind)=[];
    trainData(del_ind,:)=[];
    
    % Create a Self-Organizing Map
    dimension1 = 15;
    dimension2 = 15;
    net1= selforgmap([dimension1 dimension2]);
    % Train the Network
    [net1,tr] = train(net1,trainData');
    
    % Test the SOM Network
    trainOutputs = net1(trainData');
    testOutputs = net1(testData');
    
    %Train Neural Net
    net = fitnet([50 5]);
    net = configure(net,trainOutputs,trainTarget');
    net.inputs{1}.processFcns={'mapstd','mapminmax'};
    [net,tr] = train(net,trainOutputs,trainTarget');
    nntraintool
    
    %Test Neural Net
    lact_hat=simnet(net,testOutputs);
    crossPerf(n,1)=mean((lact_hat-testTarget).^2);
    
    
    
    
    
end