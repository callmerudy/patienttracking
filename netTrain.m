function [net,tr,target]=netTrain(trainData,O2Delivery,O2Demmand,O2Utilization,trainTarget,netShow)

   
%Define which input variables to use, in addtion to the train02* ones
%This list will be expande to 5x because of each waveform being smoothed
%by progressively larger moving average defined in loadNNFeatures.m
input_names={'map_val','map_dx','map_var','ageNormalized_hr_val','ageNormalized_hr_dx',...
             'ageNormalized_hr_var','urine_val','urine_dx','urine_var','weight_val','weight_dx'...
             'pressor_val','cardiacOutput_val','cardiacOutput_dx','cardiacOutput_var','Hb_val',...
             'HbMassBlood_val','PaCO2_val','PaCO2_dx','resp_val','resp_dx','wbc_val',...
             'temp_val','temp_dx'};


%If we assume the first two columns are pid, and tm, 
%dividing the size of trainData by M give us the number of 
%the different filters used (ie, trends estimated)
%the cell array 'use_col' only contain labels for the first
%trend condition (baseline), so we need to expand the indices
%to include the columns for each of the other trend features
M=length(use_col);
feature_offset=2;
[N,L]=size(trainData);
Nfilt=(L-feature_offset)/(M-feature_offset);
Nfeatures=M-feature_offset;
featureRep=[0:Nfeatures:(Nfilt-1)*Nfeatures];

%Remove all features that were not selected for input
rm_ind=[1:feature_offset];
Ninput=length(input_names);
for m=feature_offset+1:M
    if(isempty(strmatch(input_names,use_col,'exact')))
        %Remove selected index, and its multiples 
        %according to the Nfilts used
       rm_ind(end+1)=featureRep+m;
    end
end
if(~isempty(rm_ind))
    trainData(:,rm_ind)=[];
end


%Append Latent variable estimates to training data
trainData=[trainData O2Delivery O2Demmand O2Utilization];


%Train Neural Net
net = fitnet([50 10 5]);
net = configure(net,trainData,trainTarget');
net.inputs{1}.processFcns={'mapstd','mapminmax'};
[net,tr] = train(net,trainData,trainTarget');
nntraintool


% %Test Neural Net
% lact_hat=net(testOutputs);
% crossPerf(n,1)=mean((lact_hat'-testTarget).^2);
% subplot(3,1,n)
% scatter(lact_hat,testTarget)
% title([num2str(crossPerf(n,1))])