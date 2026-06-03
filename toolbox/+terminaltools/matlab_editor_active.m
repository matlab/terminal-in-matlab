function matlab_editor_active()
%MATLAB_EDITOR_ACTIVE Report the active MATLAB editor document.
doc = matlab.desktop.editor.getActive;
if isempty(doc)
    disp(jsonencode(struct('error', 'No active editor document')));
    return;
end

result = struct('filename', doc.Filename, 'modified', doc.Modified, ...
    'selection', doc.Selection, 'selectedText', doc.SelectedText);
disp(jsonencode(result));
end
