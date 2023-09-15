% This function handles the softcodes in the protocol.

function optotaggingPdynSoftCodeHandler(SoftCodeID)
% SoftCodeID is an integer that identifies the action that should be taken.

global microInjectionPump
global sipperPump
    
if SoftCodeID == 2 % Trigger the sipper pump
    fwrite(sipperPump, char([114 117 110 13 10]));
elseif SoftCodeID == 3 % Trigger the microinjection pump
    fwrite(microInjectionPump, char([114 117 110 13 10]));    
else
    error('Unknown soft code.')
end
