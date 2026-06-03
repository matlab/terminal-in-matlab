function matlab_editor_list()
%MATLAB_EDITOR_LIST List open MATLAB editor documents with modification status.
docs = matlab.desktop.editor.getAll;
result = struct('files', {{}});
for idx = 1:numel(docs)
    result.files{end+1} = struct('filename', docs(idx).Filename, ...
        'modified', docs(idx).Modified);
end
disp(jsonencode(result));
end
