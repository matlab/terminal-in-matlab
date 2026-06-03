function matlab_editor_read(name)
%MATLAB_EDITOR_READ Read the contents of an open MATLAB editor document.
if nargin < 1
    name = '';
end

if isempty(name)
    doc = matlab.desktop.editor.getActive;
    if isempty(doc)
        disp('No active editor document');
    else
        fprintf('File: %s\n\n', doc.Filename);
        disp(doc.Text);
    end
    return;
end

docs = matlab.desktop.editor.getAll;
found = false;
for idx = 1:numel(docs)
    if contains(docs(idx).Filename, name)
        fprintf('File: %s\n\n', docs(idx).Filename);
        disp(docs(idx).Text);
        found = true;
        break;
    end
end

if ~found
    fprintf('No open file matching "%s"\n', name);
end
end
