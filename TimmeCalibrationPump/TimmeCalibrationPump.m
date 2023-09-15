function TimmeCalibrationPump

% This protocol allows the user to calibrate the fluid dispensing system.
% It is similar to the bpod calibration code, except it allows for
% different fluid densities, it incorporates a suction system, and it
% incorporates a paper towel weight.
global BpodSystem

%% Setup (runs once before the first trial)

%--- Define parameters and trial structure
global S
S = BpodSystem.ProtocolSettings; % Loads settings file chosen in launch manager into current workspace as a struct called 'S'
if isempty(fieldnames(S))  % If chosen settings file was an empty struct, populate struct with default settings
    % Define default settings here as fields of S (i.e S.InitialDelay = 3.2)
    % Note: Any parameters in S.GUI will be shown in UI edit boxes. 
    % See ParameterGUI plugin documentation to show parameters as other UI types (listboxes, checkboxes, buttons, text)
    
    % Load the rig parameter files
    load('C:\Bpod Local\rigParams.mat','rigParams')
    
    % Set the name of the softcode handler function
    S.SoftCodeHandlerFunctionName = 'TimmeCalibrationPumpSoftCodeHandler';
    
    % Set the delay before drop release begins in seconds
    S.preDropDelay = 4;
    
    % Set the delay to wait for the pump to expel the drop
    S.dropDelay = 0.5;
    
    % Set the delay between drop releases and suction in seconds
    S.postDropDelay = 1;
    
    % Set the suction valve open time
    S.suctionTime = 2;
    
    % Set the suction time at the end of the protocol to clear the tube
    S.longSuctionTime = 7;
    
end

%--- Initialize plots and start USB connections to any modules
% BpodParameterGUI('init', S); % Initialize parameter GUI plugin

% Identify the soft code handler function for the Bpod
BpodSystem.SoftCodeHandlerFunction = S.SoftCodeHandlerFunctionName; % Provide the name of the soft code handler function

% Ask the user how many drops to dispense, the fluid density, desired
% volume, and dry paper towel weight
prompt = {'Number of Drops:','Liquid Density (g/mL):','Desired Volume (uL):',...
    'Pump Volume (uL)','Estimate of Fluid Left in Tube (g):','Suction On/Off:','Estimate of Bypassed Fluid per Drop (uL):'};
dlgtitle = 'Set Calibration Parameters';
definput = {'100','0.97','4','','0','On','0'};
dims = [1 60];
answer = inputdlg(prompt,dlgtitle,dims,definput);
nDrops = str2double(answer{1});
liqDensity = str2double(answer{2});
volGoal = str2double(answer{3});
volPump = str2double(answer{4});
lossWeight = str2double(answer{5});
if strcmp(answer{6},'On')
    suctionOpt = 'On';
elseif strcmp(answer{6},'Off')
    suctionOpt = 'Off';
else
    error('Invalid suction option input.')
end
bypassVol = str2double(answer{7});

% Tell the user to confirm the suction system is ready
f = msgbox('Confirm the suction reservoir is empty and the suction valve is open.');
uiwait(f)

%Initialize pump on COM port
global pump
pump = serial(['COM',num2str(rigParams.COM_Pump)]);
%Set all values in order to read values correctly
set(pump, 'Timeout', 60);
set(pump,'BaudRate', 9600);
set(pump, 'Parity', 'none');
set(pump, 'DataBits', 8);
set(pump, 'StopBits', 1);
set(pump, 'RequestToSend', 'off');
%Open pump data stream
fopen(pump);



%% Make the progress bar

f = waitbar(0,'Dispensing Drops');

%% Main loop (runs once per trial)
currentTrial = 1;
while currentTrial <= nDrops
    
    %--- Typically, a block of code here will compute variables for assembling this trial's state machine
    
    % Update the progress bar
    waitbar(currentTrial/nDrops,f,['Dispensing Drop ',num2str(currentTrial),' of ',num2str(nDrops)]);
    
    % Set the suction time for this trial
    if currentTrial < nDrops
        suctionTime = S.suctionTime;
    else
        suctionTime = S.longSuctionTime;
    end
    
    %--- Assemble state machine    
    sma = NewStateMachine();
    
    if strcmp(suctionOpt,'On')
        % State 1
        % - Impose a brief delay before expelling drop
        sma = AddState(sma, 'Name', 'preDropDelay', ...
            'Timer', S.preDropDelay,...
            'StateChangeConditions', {'Tup', 'dropDelay'},...
            'OutputActions', {});
        
        % State 2
        % - Wait for the pump to expel the drop
        sma = AddState(sma, 'Name', 'dropDelay', ...
            'Timer', S.dropDelay,...
            'StateChangeConditions', {'Tup', 'PostDropDelay'},...
            'OutputActions', {'SoftCode', 1});
        
        % State 3
        % - Impose a brief delay after drop release, but before suction
        sma = AddState(sma, 'Name', 'PostDropDelay', ...
            'Timer', S.postDropDelay,...
            'StateChangeConditions', {'Tup', 'ClearSipper'},...
            'OutputActions', {});
        
        % State 4
        % - Clear the sipper by suctioning off any fluid
        sma = AddState(sma, 'Name', 'ClearSipper', ...
            'Timer', suctionTime,...
            'StateChangeConditions', {'Tup', 'exit'},...
            'OutputActions', {'Valve2',1});
    elseif strcmp(suctionOpt,'Off')
        
        % State 1
        % - Impose a brief delay before expelling drop
        sma = AddState(sma, 'Name', 'preDropDelay', ...
            'Timer', S.preDropDelay,...
            'StateChangeConditions', {'Tup', 'dropDelay'},...
            'OutputActions', {});
        
        % State 2
        % - Wait for the pump to expel the drop
        sma = AddState(sma, 'Name', 'dropDelay', ...
            'Timer', S.dropDelay,...
            'StateChangeConditions', {'Tup', 'PostDropDelay'},...
            'OutputActions', {'SoftCode',1});
        
        % State 3
        % - Impose a brief delay after drop release, but before suction
        sma = AddState(sma, 'Name', 'PostDropDelay', ...
            'Timer', S.postDropDelay,...
            'StateChangeConditions', {'Tup', 'exit'},...
            'OutputActions', {});
        
    end
    
    
    SendStateMatrix(sma); % Send state machine to the Bpod state machine device
    RawEvents = RunStateMatrix; % Run the trial and return events
    
    
    %--- Package and save the trial's data, update plots
    if ~isempty(fieldnames(RawEvents)) % If you didn't stop the session manually mid-trial
        
        BpodSystem.Data = AddTrialEvents(BpodSystem.Data,RawEvents); % Adds raw events to a human-readable data struct
        BpodSystem.Data.TrialSettings(currentTrial) = S; % Adds the settings used for the current trial to the Data struct (to be saved after the trial ends)
        SaveBpodSessionData; % Saves the field BpodSystem.Data to the current data file
        
        
    end
    
    %--- This final block of code is necessary for the Bpod console's pause and stop buttons to work
    HandlePauseCondition; % Checks to see if the protocol is paused. If so, waits until user resumes.
    if BpodSystem.Status.BeingUsed == 0
        return
    end
    
    % Advance the trial count
    currentTrial = currentTrial + 1;
    
end

% Close the progress bar
close(f)

%Close pump I/O stream
fclose(pump);

% Ask the user to input the paper towel weights
prompt = {'Dry Paper Towel Weight (g):','Wet Paper Towel Weight (g):'};
dlgtitle = 'Paper Towel Weights';
definput = {'',''};
dims = [1 60];
answer = inputdlg(prompt,dlgtitle,dims,definput);
dryWeight = str2double(answer{1});
wetWeight = str2double(answer{2});

% Calculate the consumable drop volume
volDrop = 1000*((((wetWeight - dryWeight) + lossWeight)/liqDensity)/nDrops) - bypassVol;

% Display the results to the user
if volDrop > volGoal
    ratio = (volDrop - volGoal)/volGoal;
    f = msgbox(['Estimate of Consumable Drop Volume: ',num2str(volDrop,3),' uL',newline,...
        'Goal Volume: ',num2str(volGoal,3),' uL',newline,...
        'Thus, the actual volume is about ',num2str(100*ratio,2),' % too high.',newline,...
        'We suggest decreasing the pump volume setting to ',num2str(volPump*(volGoal/volDrop),3),' uL.']);
else
    ratio = (volGoal - volDrop)/volGoal;
    f = msgbox(['Estimate of Consumable Drop Volume: ',num2str(volDrop,3),' uL',newline,...
        'Goal Volume: ',num2str(volGoal,3),' uL',newline,...
        'Thus, the actual volume is about ',num2str(100*ratio,2),' % too low.',newline,...
        'We suggest increasing the pump volume setting to ',num2str(volPump*(volGoal/volDrop),3),' uL.']);
end
uiwait(f)






disp('Protocol has ended. Please press stop in the Bpod GUI.')





    


