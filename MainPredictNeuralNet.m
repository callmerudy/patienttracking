% %Script for predicting patient lactate value usign K-means
% clear all;close all;clc
%
% %Setting this flag to true, will skip any Network Training
% %and Pring the percentage of true values in the LatentVariables being
% %Estimated (currently determined by the functions: latentO2Utilization, latentO2Demmand,
% %and latentO2Delivery
% checkLatentDistributionFlag=0;
%
%
% %Load feature database lact_db
% [Npid,lact_db,target,commorbidityVal,commorbidityNames,unique_pid,use_col]=loadFeatures();
% Mcol=length(lact_db(1,:));
% Ndb=length(lact_db);
% pid_init=lact_db(:,1);
%
% %Partition the dataset into 3 parts for 3x validation
% %The N-fold validation is done in terms of number of patients, not number
% %of measurements (which may be dependent).
% %The sets should have no points from the same patients across them.
%
% Nfold=3;
% NCrossVal=ceil(Npid/Nfold)*Nfold;
%
% %Shuffle the unique patients
% shuffled_pids=unique_pid(randperm(Npid));
%
% %Columns are the Nfold, rows are the patients (not lactate measurements)
% if(Npid <NCrossVal)
%     shuffled_pids(NCrossVal)=NaN;
% end
% shuffled_pids=reshape(shuffled_pids,[NCrossVal/Nfold Nfold]);
%
% crossPerf=zeros(Nfold,1)+NaN;
% Ntest=NCrossVal/Nfold;
% Ntrain=Ntest*2; %Based 3x validation
% Ncomm=length(commorbidityNames);
%
%
% for n=1:Nfold
%
%     %Set test, training and validation data (MATLAB's NN Toolbox will take care
%     %of the training and validation steps).
%     test_unique_pid=shuffled_pids(:,n);
%     train_unique_pid=setdiff(shuffled_pids(:),test_unique_pid);
%
%     %Generate the test and training datasets & targets
%     testData=zeros(Ntest,Mcol)+NaN;
%     trainData=zeros(Ntrain,Mcol)+NaN;
%
%     testTarget=zeros(Ntest,1)+NaN;
%     trainTarget=zeros(Ntest,1)+NaN;
%
%     %Generate the test and training commorbidities
%     testComm=zeros(Ntest,Ncomm)+NaN;
%     trainComm=zeros(Ntest,Ncomm)+NaN;
%
%     test_ind=1;
%     train_ind=1;
%     old_pid=0;
%     for t=1:Ndb
%         tmp_pid=pid_init(t);
%         if(tmp_pid ~= old_pid)
%             %Use this to improve performance for repeated measurements on
%             %same patient
%             isTest=NaN;
%             if(~isempty(find(test_unique_pid == tmp_pid)))
%                 isTest=1;
%             elseif(~isempty(find(train_unique_pid == tmp_pid)))
%                 isTest=0;
%             else
%                 error('Unmatched id!!')
%             end
%             old_pid=tmp_pid;
%         end
%
%         if(isTest)
%             testData(test_ind,:)=lact_db(t,:);
%             testTarget(test_ind)=target(t);
%             commInd=find(commorbidityVal(:,1) == tmp_pid);
%             testComm(test_ind,:)=commorbidityVal(commInd,:);
%             test_ind=test_ind+1;
%         else
%             trainData(train_ind,:)=lact_db(t,:);
%             trainTarget(train_ind)=target(t);
%             commInd=find(commorbidityVal(:,1) == tmp_pid);
%             trainComm(train_ind,:)=commorbidityVal(commInd,:);
%             train_ind=train_ind+1;
%         end
%     end
%
%     %Remove any NaN points
%     del_ind=find(isnan(testTarget)==1);
%     testTarget(del_ind)=[];
%     testData(del_ind,:)=[];
%     testComm(del_ind,:)=[];
%
%     del_ind=find(isnan(trainTarget)==1);
%     trainTarget(del_ind)=[];
%     trainData(del_ind,:)=[];
%     trainComm(del_ind,:)=[];
%
%     %Estimate latent variables
%     netShow=1; %displays regression plot of NN on target values
%     chckLatentDistFlag=0;
%     [netO2Delivery,trO2Delivery,targetO2Delivery]=latentO2Delivery(trainData,trainComm,commorbidityNames,netShow,chckLatentDistFlag);
%     [netO2Demmand,trO2Demmand,targetO2Demmand]=latentO2Demmand(trainData,trainComm,commorbidityNames,netShow,chckLatentDistFlag);
%     [netO2Utilization,trO2Utilization,targetO2Utilization]=latentO2Utilization(trainData,trainComm,commorbidityNames,netShow,chckLatentDistFlag);
%
%     %save temp_nets

clear all;close all;clc
load temp_nets
%Estimate the latent variables
useLatent=0;

%Loop through different NN structures
%Trading off between complexity vs over-fitting
net_dim={[200],...
    [5 5],...
    [20 5],...
    [30 5],...
    [50 5],...
    [100 5],...
    [5 10],...
    [20 10],...
    [30 10],...
    [20 20],...
    };

%Set the following inputs to be used by the Neural Networks
input_names={'map_val','map_dx','map_var','ageNormalized_hr_val','ageNormalized_hr_dx',...
    'ageNormalized_hr_var','urine_val','urine_dx','urine_var','weight_val','weight_dx'...
    'cardiacOutput_val','cardiacOutput_dx','PaCO2_val','resp_val'...
    };

if(useLatent)
    O2Delivery = netO2Delivery(trainData')';
    O2Demmand = netO2Demmand(trainData')';
    O2Utilization = netO2Utilization(trainData')';
else
    O2Delivery=[];
    O2Demmand=[];
    O2Utilization=[];
end

%Crop data to remove what we are not usign as inputs
trainNNData=cropData(trainData,input_names,use_col,O2Delivery,O2Demmand,O2Utilization,useLatent);

Nnet_dim=length(net_dim);
NET_0=cell(Nnet_dim,1);
TR_0=cell(Nnet_dim,1);
scores_0=zeros(Nnet_dim,1)+NaN;
display('Training NNs...')
for ndim=1:Nnet_dim
    %Train the final NN for estimation of Lactate measurements
    %Each NN structure is initialized/trained 10 times in order to optmize
    %on the initial conditions parameter
    testN=10;
    NET=cell(testN,1);
    TR=cell(testN,1);
    scores=zeros(testN,1)+NaN;
    parfor i=1:testN
        [tmp_net,tmp_tr]=lactateNN(trainNNData,trainTarget,netShow,net_dim{ndim});
        NET{i}=tmp_net;
        TR{i}=tmp_tr;
        scores(i)=tmp_tr.best_tperf;
    end
    %Find best NN for this structure
    [best_score,best]=min(scores);
    net=NET{best};
    tr=TR{best};
    
    display(['Best score for NN with dim: ' num2str((net_dim{ndim})) ' = ' ...
        num2str(best_score)])
    
    %Save best results for this type of structure
    NET_0{ndim}=net;
    TR_0{ndim}=tr;
    scores_0(ndim)=scores(best);
    %Cache results in case of a crash
    save temp_NN_cache
end

%Find best overall structure
[~,best]=min(scores_0);
net=NET_0{best};
tr=TR_0{best};


display('***Done training NNs...')
yhat = net(trainNNData');
subplot(212)
plotregression(trainTarget,yhat);




%end
