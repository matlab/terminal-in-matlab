function matlab_editor_selection()
%MATLAB_EDITOR_SELECTION Return the selected text in the active editor.
doc = matlab.desktop.editor.getActive;
if isempty(doc)
    disp('No active editor document');
elseif isempty(doc.SelectedText)
    disp('No text selected');
else
    disp(doc.SelectedText);
end
end
