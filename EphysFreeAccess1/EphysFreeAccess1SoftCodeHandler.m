% This function handles the softcodes in the protocol.

function EphysFreeAccess1SoftCodeHandler(SoftCodeID)
% SoftCodeID is an integer that identifies the action that should be taken.


global pahandleS1
global pump


if SoftCodeID == 1
    % Play Sound 1
    
%     PsychPortAudio('Start', pahandleS1);
    
elseif SoftCodeID == 2
    
    % Trigger the pump
    fwrite(pump, char([114 117 110 13 10]));
    
else
    error('Unknown soft code.')
end
