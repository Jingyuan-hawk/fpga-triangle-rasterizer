function [frame, coverage, stats] = rasterize_triangles(triangles, width, height, mode)
%RASTERIZE_TRIANGLES 2-D triangle rasterizer reference model.
%   [FRAME,COVERAGE,STATS] = RASTERIZE_TRIANGLES(TRIANGLES,W,H,MODE)
%   accepts a struct array. Each element has:
%       xy    - 3-by-2 vertex coordinates [x y], in pixels
%       color - RGB565 value, 0..65535
%
%   MODE is 'double' (floating-point oracle) or 'fixed' (integer model).
%   The fixed model rounds coordinates to 1/16 pixel, evaluates edge
%   functions at pixel centers, and advances them by additions only.
%   Pixel (x,y) is stored in FRAME(y+1,x+1). Later triangles overwrite
%   earlier ones. Depth testing, blending, and clipping of triangles to
%   new vertices are not part of this first-stage model.

    if nargin < 4
        mode = 'fixed';
    end
    validateattributes(width, {'numeric'}, {'scalar','integer','>=',1,'<=',4096});
    validateattributes(height, {'numeric'}, {'scalar','integer','>=',1,'<=',4096});
    if ~isstruct(triangles)
        error('triangles must be a struct array with xy and color fields.');
    end
    mode = char(mode);
    if ~strcmp(mode, 'double') && ~strcmp(mode, 'fixed')
        error('mode must be ''double'' or ''fixed''.');
    end

    frame = zeros(height, width, 'uint16');
    coverage = false(height, width);
    stats = struct('triangles', numel(triangles), ...
                   'degenerate', 0, 'testedPixels', 0, 'emittedPixels', 0);
    subpixel = int64(16);

    for t = 1:numel(triangles)
        xy = triangles(t).xy;
        color = triangles(t).color;
        validateattributes(xy, {'numeric'}, {'size',[3 2], 'real', 'finite'});
        if any(abs(xy(:)) > 4096)
            error('Vertex coordinates must be within [-4096,4096].');
        end
        validateattributes(color, {'numeric'}, ...
            {'scalar','integer','>=',0,'<=',65535});
        color = uint16(color);

        if strcmp(mode, 'fixed')
            p = int64(round(double(xy) * double(subpixel)));
            area = edge_value(p(1,:), p(2,:), p(3,:));
        else
            p = double(xy);
            area = edge_value(p(1,:), p(2,:), p(3,:));
        end
        if area == 0
            stats.degenerate = stats.degenerate + 1;
            continue;
        end
        if area < 0
            p([2 3],:) = p([3 2],:);
        end

        % For screen coordinates with y increasing downward, this makes
        % the top and left edges inclusive; shared edges are drawn once.
        a = p([1 2 3],:);
        b = p([2 3 1],:);
        dx = b(:,1) - a(:,1);
        dy = b(:,2) - a(:,2);
        inclusive = (dy < 0) | ((dy == 0) & (dx > 0));

        if strcmp(mode, 'fixed')
            xyPixels = double(p) / double(subpixel);
        else
            xyPixels = p;
        end
        x0 = max(0, ceil(min(xyPixels(:,1)) - 0.5));
        x1 = min(width - 1, floor(max(xyPixels(:,1)) - 0.5));
        y0 = max(0, ceil(min(xyPixels(:,2)) - 0.5));
        y1 = min(height - 1, floor(max(xyPixels(:,2)) - 0.5));
        if x0 > x1 || y0 > y1
            continue;
        end

        if strcmp(mode, 'fixed')
            px0 = int64(x0) * subpixel + subpixel/2;
            py0 = int64(y0) * subpixel + subpixel/2;
            edgeRow = dx .* (py0 - a(:,2)) - dy .* (px0 - a(:,1));
            stepX = -dy * subpixel;
            stepY =  dx * subpixel;
            for y = y0:y1
                edge = edgeRow;
                for x = x0:x1
                    stats.testedPixels = stats.testedPixels + 1;
                    if all((edge > 0) | ((edge == 0) & inclusive))
                        frame(y+1,x+1) = color;
                        coverage(y+1,x+1) = true;
                        stats.emittedPixels = stats.emittedPixels + 1;
                    end
                    edge = edge + stepX;
                end
                edgeRow = edgeRow + stepY;
            end
        else
            % Independent floating-point oracle: evaluate each pixel
            % directly rather than reusing the incremental edge values.
            for y = y0:y1
                for x = x0:x1
                    sample = [x + 0.5, y + 0.5];
                    edge = dx .* (sample(2) - a(:,2)) ...
                         - dy .* (sample(1) - a(:,1));
                    stats.testedPixels = stats.testedPixels + 1;
                    if all((edge > 0) | ((edge == 0) & inclusive))
                        frame(y+1,x+1) = color;
                        coverage(y+1,x+1) = true;
                        stats.emittedPixels = stats.emittedPixels + 1;
                    end
                end
            end
        end
    end
end

function value = edge_value(a, b, p)
    value = (b(1)-a(1)) * (p(2)-a(2)) ...
          - (b(2)-a(2)) * (p(1)-a(1));
end
