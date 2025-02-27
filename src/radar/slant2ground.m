function [ s, h ] = slant2ground( r, thet )
%SLANT2GROUND Convert from slant range and elevation to ground range and height.
%
% [ s, h ] = slant2ground( r, thet )
%
% Input:
%   r       range along radar path
%   thet 	elevation angle in degrees
% Output:  
%   s    	range along ground (great circle distance)
%   h    	height above earth 
%
% Uses spherical earth with radius 6371.2 km
%
% From Doviak and Zrnic 1993 Eqs. (2.28b) and (2.28c)
% 
% See also
% https://github.com/deeplycloudy/lmatools/blob/master/lmatools/coordinateSystems.py
%

earth_radius = 6371200; % from NARR GRIB file
multiplier = 4/3; % correct for atmospheric refraction

r_e = earth_radius * multiplier; % earth effective radius

thet = deg2rad(thet);

h = sqrt(r.^2 + r_e^2 + 2 * r_e * r .* sin(thet)) - r_e; % law of cosines
s = r_e * asin( r .* cos(thet) ./ ( r_e + h ) );

end
