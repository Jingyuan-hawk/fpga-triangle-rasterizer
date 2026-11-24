function demo_rasterizer(showFigure)
%DEMO_RASTERIZER Run correctness checks and render an example scene.
%   Run demo_rasterizer or demo_rasterizer(false) for headless verification.
    if nargin < 1
        showFigure = true;
    end

    % Two triangles tile an 80-by-80 square. The shared diagonal must
    % produce neither cracks nor double writes.
    tile(1).xy = [20 20; 100 20; 100 100];
    tile(1).color = hex2dec('F800');
    tile(2).xy = [20 20; 100 100; 20 100];
    tile(2).color = hex2dec('07E0');
    [tileFrame, tileMask, tileStats] = rasterize_triangles(tile, 128, 128, 'fixed');
    assert(nnz(tileMask) == 80*80, 'Shared-edge coverage is wrong.');
    assert(tileStats.emittedPixels == 80*80, 'Shared edge was written twice.');

    % Check clockwise and counterclockwise vertex orders, fractional
    % coordinates, screen-edge clipping, and a degenerate triangle.
    scene(1).xy = [12 12; 185.25 30.5; 45.75 200];
    scene(1).color = hex2dec('F800');
    scene(2).xy = [60 45; 210 205; 290 35];
    scene(2).color = hex2dec('07E0');
    scene(3).xy = [-20 150; 160 260; 315 120];
    scene(3).color = hex2dec('001F');
    scene(4).xy = [15 15; 30 30; 45 45];
    scene(4).color = hex2dec('FFFF');

    [reference, ~, referenceStats] = rasterize_triangles(scene, 320, 240, 'double');
    [fixed, ~, fixedStats] = rasterize_triangles(scene, 320, 240, 'fixed');
    mismatch = nnz(reference ~= fixed);
    fprintf('Tiled square: %d covered, %d emitted\n', nnz(tileMask), tileStats.emittedPixels);
    fprintf('Scene: %d pixels differ; %d fixed pixels emitted; %d degenerates\n', ...
        mismatch, fixedStats.emittedPixels, fixedStats.degenerate);
    assert(mismatch == 0, 'Double and fixed model outputs differ.');
    assert(referenceStats.degenerate == 1 && fixedStats.degenerate == 1);
    assert(any(tileFrame(:) == uint16(hex2dec('F800'))));

    if showFigure
        figure('Name','Triangle rasterizer reference');
        image(rgb565_to_rgb(fixed));
        axis image off;
        title('320 x 240 | RGB565 | 1/16-pixel fixed-point coordinates');
    end
end

function rgb = rgb565_to_rgb(frame)
    v = uint16(frame);
    r = double(bitand(bitshift(v,-11),31)) / 31;
    g = double(bitand(bitshift(v,-5),63)) / 63;
    b = double(bitand(v,31)) / 31;
    rgb = cat(3,r,g,b);
end
