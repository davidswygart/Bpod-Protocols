function optotaggingPdyn
% optotaggingPdyn is a task protocol built off of EphysFreeAccess1 that is
% specifically designed to be used in the ephys rig for neuropixel
% recording, laser activation, and brain microinjections
%
%   Task: Switching between audio and visual states. Trigger injection of
%   alcohol after collecting baseline. Pulse laser at the end of the
%   recording to identify optotagged neurons.
%
%   Other Details:
%       - alcohol/saline is delivered by syring pump
% 

global BpodSystem

%% Setup (runs once before the first trial)

%--- Define parameters and trial structure
global S
S = BpodSystem.ProtocolSettings; % Loads settings file chosen in launch manager into current workspace as a struct called 'S'
if isempty(fieldnames(S))  % If chosen settings file was an empty struct, populate struct with default settings
    % Define default settings here as fields of S (i.e S.InitialDelay = 3.2)
    % Note: Any parameters in S.GUI will be shown in UI edit boxes. 
    % See ParameterGUI plugin documentation to show parameters as other UI types (listboxes, checkboxes, buttons, text)
    
    
    % Set the name of the softcode handler function
    S.SoftCodeHandlerFunctionName = 'optotaggingPdynSoftCodeHandler';
    
    % COM Ports
%     S.COM_Rot = rigParams.COM_Rot; % Rotary Encoder
%     S.COM_F2TTL = rigParams.COM_F2TTL; % Frame2TTL sensor 
    S.COM_microInjectionPump = 'COM9';
    S.COM_sipperPump = 'COM4';
    
    % Set the pretrial delay period in seconds.
%     S.PretrialDelayTime = 0.5;
    S.PretrialDelayTime = 4;
    
    % Set the delay in seconds after reward delivery before droplet is
    % suctioned off.
%     S.PostRewardDelay = 15;
    S.PostRewardDelay = 10;
    
    % Set the sipper clear time in seconds. This is the amount of time that suction
    % will be applied to remove any excess drops.
    S.SipperClearTime = 1;
    
end

%--- Initialize plots and start USB connections to any modules
% BpodParameterGUI('init', S); % Initialize parameter GUI plugin

% Identify the soft code handler function for the Bpod
BpodSystem.SoftCodeHandlerFunction = S.SoftCodeHandlerFunctionName; % Provide the name of the soft code handler function

% Make a directory to hold non-state machine data files
mkdir([BpodSystem.Path.CurrentDataFile(1:(end - 4)),'AdditionalData']);
mkdir([BpodSystem.Path.CurrentDataFile(1:(end - 4)),'Video']);
dataDir = [BpodSystem.Path.CurrentDataFile(1:(end - 4)),'AdditionalData',filesep];
videoDir = [BpodSystem.Path.CurrentDataFile(1:(end - 4)),'Video'];

% Obtain information from the user
dlgtitle = 'Set Calibration Parameters';
prompt = {...
    'Time Limit (Minutes):',...
    'Alcohol Concentration (Percent):',...
    'Drop Volume (uL):',...
    'Pump Volume Setting (uL):',...
    'Animal Weight (Grams):',...
    'Liquid Density (g/mL):',...
    'Estimate of Fluid Left in Tube (g):'...
    };

definput = {... % default values
    '30',... % time limit
    '20',... % alcohol concentration
    '4',... % drop volume
    '',... % pump volume
    '',... % animal weight
    '0.97',... % liquid density
    '0'... % fluid left in tube
    };
dims = [1 60];
answer = inputdlg(prompt,dlgtitle,dims,definput);
timeLimit = str2double(answer{1});
alcCon = str2double(answer{2});
S.alcCon = alcCon;
dropVol = str2double(answer{3});
S.dropVol = dropVol;
S.pumpVolSetting = str2double(answer{4});
animWeight = str2double(answer{5});
S.animWeight = animWeight;
doseConv = (dropVol/1000)*0.789*(alcCon/100)/(animWeight/1000);
S.liqDensity = str2double(answer{6});
S.lossWeight = str2double(answer{7});

% Tell the user to confirm the suction system is ready
f = msgbox('Confirm the suction reservoir is empty and the suction valve is open.');
uiwait(f)

% Ask the user if they performed sipper alignment
f = msgbox('Make sure to perform sipper alignment on video computer.');
uiwait(f)

% Tell the user to start the video recording.
f = msgbox(['Please start the video recording in FlyCapture2.',newline,newline,...
    'Follow these steps to start video recording.',newline,...
    'Open FlyCapture2.',newline,...
    'Click OK.',newline,...
    'Click File -> Capture Image or Video Sequence.',newline,...
    'The video filename should be ',videoDir,'\video.',newline,...
    'Recording mode should be set to Buffered.',newline,...
    'Click the videos tab, video recording type should be M-JPEG.',newline,...
    'Click use camera frame rate.',newline,...
    'Set AVI split size to 100.',newline,...
    'Set JPEG compression quality to 50%.']);
uiwait(f)

%Initialize microinjection pump on COM port
global microInjectionPump
microInjectionPump = serial(S.COM_microInjectionPump);
%Set all values in order to read values correctly
set(microInjectionPump, 'Timeout', 60);
set(microInjectionPump,'BaudRate', 9600);
set(microInjectionPump, 'Parity', 'none');
set(microInjectionPump, 'DataBits', 8);
set(microInjectionPump, 'StopBits', 1);
set(microInjectionPump, 'RequestToSend', 'off');
%Open pump data stream
fopen(microInjectionPump);

%Initialize sipper pump on COM port
global sipperPump
sipperPump = serial(S.COM_sipperPump);
%Set all values in order to read values correctly
set(sipperPump, 'Timeout', 60);
set(sipperPump,'BaudRate', 9600);
set(sipperPump, 'Parity', 'none');
set(sipperPump, 'DataBits', 8);
set(sipperPump, 'StopBits', 1);
set(sipperPump, 'RequestToSend', 'off');
%Open pump data stream
fopen(sipperPump);


%% Prompt the user to proceed

disp(' ')
disp(' ')
input('The protocol is ready to run. Press any key when you are ready to start the protocol.','s');
tOverall = tic;

%% Main loop (runs once per trial)
currentTrial = 1;
while ((toc(tOverall)/60) < timeLimit)
    
    %--- Typically, a block of code here will compute variables for assembling this trial's state machine
    
    disp(['Starting trial ',num2str(currentTrial),'.'])
    disp(['There are about ',num2str(timeLimit - (toc(tOverall)/60),3),' minutes left in this session.'])
    disp('Starting pre-trial dead time.')
    
    tLocal = tic;
    
    %--- Assemble state machine    
    sma = NewStateMachine();
    
    % State 1
    % - Impose a brief pretrial delay, turn on IR LED to sync video
    sma = AddState(sma, 'Name', 'PretrialDelay', ...
        'Timer', S.PretrialDelayTime,...
        'StateChangeConditions', {'Tup', 'OpenFluidValve'},...
        'OutputActions', {'PWM2',255,'BNC1',255});

    % State 2
    % - Open the valve to deliver fluid
    sma = AddState(sma, 'Name', 'OpenFluidValve', ...
        'Timer', 0.1,...
        'StateChangeConditions', {'Tup', 'PostRewardDelay'},...
        'OutputActions', {'SoftCode', 2});
    
    % State 3
    % - Impose a delay to allow for consumption
    sma = AddState(sma, 'Name', 'PostRewardDelay', ...
        'Timer', S.PostRewardDelay,...
        'StateChangeConditions', {'Tup', 'ClearSipper'},...
        'OutputActions', {});
    
    % State 4
    % - Clear the sipper by suctioning off any fluid
    sma = AddState(sma, 'Name', 'ClearSipper', ...
        'Timer', S.SipperClearTime,...
        'StateChangeConditions', {'Tup', 'LaserTTL'},...
        'OutputActions', {'Valve2',1});

    if currentTrial==1
        % State 5 
        % - TTL to laser
        sma = AddState(sma, 'Name', 'LaserTTL', ...
            'Timer', 1,...
            'StateChangeConditions', {'Tup', 'MicroInject'},...
            'OutputActions', {'BNC2',255});
    
        % State 6
        % run microinjection pump
        sma = AddState(sma, 'Name', 'MicroInject',...
            'Timer', 120,...
            'StateChangeConditions', {'Tup', 'exit'},...
            'OutputActions', {'SoftCode', 3});
    else
        % State 5 
        % - TTL to laser
        sma = AddState(sma, 'Name', 'LaserTTL', ...
            'Timer', 1,...
            'StateChangeConditions', {'Tup', 'exit'},...
            'OutputActions', {'BNC2',255});
    end


    
    
    SendStateMatrix(sma); % Send state machine to the Bpod state machine device
    
    disp(['Finished pre-trial dead time. It took ',num2str(toc(tLocal)),' seconds. Starting trial now.'])
    
    RawEvents = RunStateMatrix; % Run the trial and return events
    
    
    %--- Package and save the trial's data, update plots
    if ~isempty(fieldnames(RawEvents)) % If you didn't stop the session manually mid-trial
        
        disp('Starting post-trial dead time.')
        
        tLocal = tic;
        BpodSystem.Data = AddTrialEvents(BpodSystem.Data,RawEvents); % Adds raw events to a human-readable data struct
        BpodSystem.Data.TrialSettings(currentTrial) = S; % Adds the settings used for the current trial to the Data struct (to be saved after the trial ends)
        SaveBpodSessionData; % Saves the field BpodSystem.Data to the current data file
        toc(tLocal)
        %--- Typically a block of code here will update online plots using the newly updated BpodSystem.Data
        disp('Finished post-trial dead time.')
    end
    
    %--- This final block of code is necessary for the Bpod console's pause and stop buttons to work
    HandlePauseCondition; % Checks to see if the protocol is paused. If so, waits until user resumes.
    if BpodSystem.Status.BeingUsed == 0
        return
    end

    % Advance the trial count
    currentTrial = currentTrial + 1;
end

% Save plot data
nTrialsCompleted = currentTrial - 1;
save([dataDir,'plotData.mat'],'nTrialsCompleted')

% Tell the user to stop the video recording
f = msgbox('Stop the video recording on the video recording computer!');
uiwait(f)

% Give the user the option to retake the sipper alignment photo
f = msgbox('If you wish to retake the sipper alignment photo, do so now on the video recording computer.');
uiwait(f)

% Tell the user to remove the animal from the rig.
f = msgbox('Remove the animal from the rig.');
uiwait(f)

% Ask the user to input the paper towel weights
prompt = {'Dry Paper Towel Weight (g):','Wet Paper Towel Weight (g):','Weight of Misc. Lost Fluid (g):'};
dlgtitle = 'Suction Reservoir Paper Towel Weights';
definput = {'','','0'};
dims = [1 60];
answer = inputdlg(prompt,dlgtitle,dims,definput);
dryWeight = str2double(answer{1});
wetWeight = str2double(answer{2});
miscLostWeight = str2double(answer{3});

% Calculate various measurements of consumption and loss
volDispensed = nTrialsCompleted*dropVol/1000; % Volume in mL dispensed assuming each drop was dropVol microliters
volCollected = (wetWeight - dryWeight + S.lossWeight - miscLostWeight)/S.liqDensity; % Volume in mL dispensed, but not consumed
save([dataDir,'fluidMeasurements.mat'],'volDispensed','volCollected')

% Display the estimates of the amount consumed
msgbox(['Consumption (Fluid Lost Method): ',num2str((volDispensed - volCollected)*0.789*(alcCon/100)/(animWeight/1000),4),' g/kg']);

%Close pump I/O stream
fclose(microInjectionPump);
fclose(sipperPump);

% Clear the hi-fi module port
clear H




disp('Protocol has ended. Please press stop in the Bpod GUI.')





    


