classdef NWP

    % NWP abstract base class for numerical weather model data
    %
    % Instantiaions of this class provide a common interface to accessing
    % data from numerical weather models on different grids.
    % 
    % See file for 
    %
    % See also NARR, NAM3D, NAM3D_212, NAM3D_218
    
    methods (Abstract,Static)
        [ g ]                    = grid( );
        [ levels ]               = pressure_levels( );
        [ old_proj ]             = set_proj( );
        [ filename ]             = get_filename( time, type );
        [ u_varname, v_varname ] = wind_varnames( )
    end
    
    methods (Static)
        function reset_proj( proj )
            %RESET_PROJ Reset map projection cached value
            
            global MAP_PROJECTION MAP_VAR_LIST MAP_COORDS
            
            MAP_PROJECTION = proj.MAP_PROJECTION;
            MAP_VAR_LIST = proj.MAP_VAR_LIST;
            MAP_COORDS = proj.MAP_COORDS;
        end
    end
    
    methods
        
        function gen_consts(self)
            % GEN_CONSTS Generate struct describing the grid in projected
            %            coordinates. Works by reading the sample file and
            %            using map projection.
            
            wind_file = self.sample_file();            
            [uwind, ~, grid] = self.read_wind(wind_file);
            
            sz = size(uwind);
            
            [X, Y] = self.ll2xy(grid.lon, grid.lat);
            
            % Rows of X and cols of Y are identical to ~1e-14
            %    Take average to get "official" x/y spacings
            
            x = mean(X,1);
            y = mean(Y,2);
            
            [ny, nx] = size(X);
            
            fprintf('s.nx = %d;\n', nx);
            fprintf('s.ny = %d;\n', ny);
            fprintf('s.nz = %d;\n', sz(1));
            fprintf('s.sz = %s;\n', mat2str(sz));
            fprintf('s.x0 = %.15f;\n', x(1));
            fprintf('s.y0 = %.15f;\n', y(1));
            fprintf('s.dx = %.15f;\n', mean(diff(x)));
            fprintf('s.dy = %.15f;\n', mean(diff(y)));
        end
        
        
        function [ k ] = height2level( self, height )
            %HEIGHT2LEVEL Convert from height to pressure index for NARR data
            %
            %   k = narr_height2level( height )
            %
            % Input:
            %   height - matrix of heights (units: m above mean sea level)
            %
            % Output:
            %   k - vertical index into NARR 3D array
            %
            % See also LEVEL2HEIGHT, HEIGHT2PRESSURE
            
            % Get atmospheric pressure at user-supplied heights
            pressure = height2pressure(height);
            
            % Get pressure levels and reverse indices so pressure levels are increasing
            pressure_levels = self.pressure_levels();
            pressure_levels = pressure_levels(end:-1:1);
            
            % Get edges between two pressure levels
            edges = pressure_levels(1:end-1) + diff(pressure_levels)/2;
            edges = [-inf; edges; inf];
            
            % Assign input pressure values into bins based on these edges
            [~, k] = histc(pressure, edges);
            
            % Reverse indices again
            k = numel(pressure_levels) - k + 1;
            
        end
        
        function [ height ] = level2height( self, k )
            %LEVEL2HEIGHT Convert from pressure index to height for NARR data
            %
            %   height = NARR.level2height( k )
            %
            % Input:
            %   k - vertical index into NARR 3D array
            %
            % Output:
            %   height - matrix of heights (units: m above mean sea level)
            %
            % See also HEIGHT2LEVEL, PRESSURE2HEIGHT
            
            levels = self.pressure_levels();
            height = pressure2height(levels(k));
            
        end
        
        function [ x, y ] = ll2xy( self, lon, lat )
            %NARR_LL2XY Convert from lon, lat to NARR x,y coordinates
            
            old_proj = self.set_proj();
            
            lon(lon > 0) = lon(lon > 0) - 360;
            [x, y] = m_ll2xy(lon, lat);
            
            self.reset_proj(old_proj);
            
        end
        
        function [ lon, lat ] = xy2ll( self, x, y )
            %NARR_XY2LL Convert from NARR x,y coordinates to lon,lat
            
            old_proj = self.set_proj();
            
            [lon, lat] = m_xy2ll(x, y);
            lon(lon < -180) = lon(lon < -180) + 360;
            
            self.reset_proj(old_proj);
        end
        
        function [ i, j ] = xy2ij( self, x, y )
            %XY2IJ Convert from NARR x,y coordinates to i,j indices into NARR grid
            %
            % Find the closest grid point to given x,y point
            
            s = self.grid();
            [i, j] = xy2ij(x, y, s);
        end
        
        function [u, v, speed, direction, elev] = wind_profile(self, u_wind, v_wind, lon, lat, min_elev, max_elev)
            %WIND_PROFILE Get weather model vertical wind profile for specified location
            %
            %  [u, v, speed, direction, elev] =
            %     nwp.wind_profile( u_wind, v_wind, lon, lat, min_elev, max_elev )
            %
            % Inputs:
            %   nwp                 NWP object (for coordinate conversions)
            %   u_wind, v_wind      3D wind matrices from weather model
            %   lon, lat            location for profile
            %   min_elev, max_elev  Starting and ending elevations
            %
            % Outputs:
            %   u            East-west wind component
            %   v            North-south wind component
            %   speed        Wind speed (m/s)
            %   direction    Wind direction (degrees from north; direction blowing TO)
            %   elev         Elevation in meters
            %
            % Each output is an n x 1 vector where the ith entry corresponds to the ith
            % pressure level, starting from the pressure level closest to min_elev
            % and ending at the pressure level closest to max_elev. The values of the
            % output vectors give the measurement at the 3D grid point at that
            % pressure level and closest to lat/lon in the horizontal plane.
            %
            
            if nargin < 3
                error('First three arguments (weathermodel, u_wind and v_wind) are required');
            end
            
            if nargin < 4
                error('Arguments lon and lat are required');
            end
            
            if nargin < 6
                min_elev = 0;
            end
            
            if nargin < 7
                max_elev = realmax();
            end
            
            % TODO: replace narr_... by calls to weather_model struct...
            % get the coordinates for the radar station
            [x, y] = self.ll2xy(lon, lat);
            [i, j] = self.xy2ij(x, y);
            
            %create height bins (translate heights to indices)
            start_bin = self.height2level(min_elev);
            end_bin   = self.height2level(max_elev);
            levels    = (start_bin:end_bin)';
            
            %compute the wind velocity at each bin
            u = u_wind(levels, i, j);
            v = v_wind(levels, i, j);
            
            [theta, radius] = cart2pol(u, v);
            direction = pol2cmp(theta);
            speed = radius;
            elev = self.level2height(levels);
        end
        
        function [ vel, lon, lat, height ] = radial_vel( self, u_wind, v_wind, range, az, elev, lon0, lat0, height0 )
            %RADIAL_VEL Get radialized wind velocity from weather model data
            %
            % [ vel,lon,lat ] = nwp.radial_vel( u_wind, v_wind, range, az, elev, lon0, lat0, height0 )
            %
            % Inputs:
            %   nwp              NWP object (for coordinate conversions)
            %   u_wind, v_wind   3D wind components read from NWP data
            %   range, az, elev  Pulse volume coordinates (see below)
            %   lon0             Longitude of radar station
            %   lat0             Latitude of radar station
            %   height0          Height of radar station in meters
            %
            % Outputs:
            %   vel              Radialized wind matrix
            %   lon, lat         Pulse volume coordinate in lon,lat
            %
            % The three coordinate matrices (range, az, elev) should have the same size
            % and will specify the size of the output. The matrices can be
            % multidimensional.
            %
            % The output value vel(i1,i2,...,ik) is the radial component of the NARR
            % wind velocity at the 3D location specified in polar coordinates by
            %
            %   range(i1,...,ik), az(i1,...,ik), elev(i1,...,ik)
            %
            % The coordinates of the corresponding pulse-volume in earth-referenced
            % lon, lat, height coordinate system are:
            %
            %  lon(i1,...,ik), lat(i1,...,ik), height(i1,...,ik)
            %
            
            % Convert from (beam range, elev angle) to (great circle distance, height)
            [dist, height] = slant2ground(range, elev);
            height = height + height0;
            
            sz = size(az);
            
            % Now compute (az, dist, z) for each pixel
            %[az, dist, height] = expand_coords(az, dist, height);
            
            % Convert from (az, dist) relative to station to absolute (lat, lon) (aka "reckoning")
            [lon, lat] = m_fdist(lon0, lat0, az(:), dist(:), 'sphere');
            lon = lon-360;
            
            % TODO: replace all narr_... calls by weather_model... calls
            
            % Convert to NARR x,y and then i,j coordinates
            [x, y] = self.ll2xy(lon, lat);
            [i, j] = self.xy2ij(x, y);
            k = self.height2level(height);
            
            % Now do the lookup
            %   First do this using linear indices
            ind = sub2ind(size(u_wind), k(:), i(:), j(:));
            u = double(u_wind(ind));
            v = double(v_wind(ind));
            
            %   Then reshape into matrices
            u = reshape(u, sz);
            v = reshape(v, sz);
            
            vel = radialize(az, elev, u, v);
            
        end
        
        function [ u_wind, v_wind, grid ] = read_wind( self, wind_file, retries, pause_len )
            %READ_WIND Read u and v wind from NWP file
            %
            %   [ u_wind, v_wind, grid ] = read_wind( wind_file, retries, pause_len )
            %
            % Inputs:
            %   wind_file   Filename of NARR 3D file (e.g. merged_AWIP32.2010091100.3D)
            %   retries     Number of times to retry (default: 3)
            %   pause_len   Time to pause between retries (default: 15)
            %
            % Outputs:
            %   u_wind      East-west wind component
            %   v_wind      North-south wind component
            %   grid        Grid struct from grib file
            %
            % The output matrices are three-dimensional. They give data for the
            % complete domain of the numerical weather model.
            %
            % We implemented the retry mechanism after observing failures when running
            % many jobs on a cluster---possibly due to simultaneous access to the same
            % file being poorly handled by the njtbx library (?).
            
            if nargin < 3
                retries = 3;
            end
            
            if nargin < 4
                pause_len = 15;
            end
            
            if ~exist( wind_file, 'file');
                error('File does not exist: %s', wind_file);
            end
            
            [ u_var, v_var] = self.wind_varnames();
            
            while retries > 0
                try
                    u_wind = nj_grid_varget(wind_file, u_var);                    
                    if nargout >= 2
                        [v_wind, grid] = nj_grid_varget(wind_file, v_var);
                    end
                    retries = 0;
                catch err
                    retries = retries - 1;
                    fprintf('WARNING: Failed to read wind file:\n');
                    fprintf('%s', getReport(err));
                    
                    if retries > 0
                        fprintf('Pausing %d seconds. %d attempts remaining\n', pause_len, retries);
                        pause(pause_len);
                    else
                        rethrow(err);
                    end
                end
            end
        end
        
    end
end